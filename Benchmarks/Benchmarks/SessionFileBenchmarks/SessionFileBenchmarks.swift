import AskAgentCore
import Benchmark
import Foundation
import System

// One change = one record appended and flushed. This is the per-turn persistence cost the action
// budget pays, measured through `SessionFile` itself, at each durability level.
private let payload = SessionPayload.assistant(String(repeating: "x", count: 400))

private func scratchPath() -> FilePath {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ask-bench-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return FilePath(directory.appending(path: "s.jsonl").path)
}

let benchmarks: @Sendable () -> Void = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .syscalls], maxDuration: .seconds(3), maxIterations: 2_000)

    // Does a change cost more as the session grows? Measured without flushing, so only ask's work shows.
    for size in [0, 10_000, 100_000] {
        Benchmark("append/none after \(size) entries") { benchmark in
            var file = try SessionFile.create(at: scratchPath(), durability: .none)
            for _ in 0 ..< size { try file.append(payload) }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try file.append(payload))
            }
            benchmark.stopMeasurement()
        }
    }

    contextBenchmarks()
    capBenchmarks()

    for (name, durability) in DurabilityCase.all {
        Benchmark("append/\(name)") { benchmark in
            var file = try SessionFile.create(at: scratchPath(), durability: durability)
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                blackHole(try file.append(payload))
            }
            benchmark.stopMeasurement()
        }
    }
}
