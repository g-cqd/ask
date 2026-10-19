import AskAgentCore
import Benchmark
import Foundation
import System

// What starting or resuming a run pays for its session, once per run: creating an empty file, and opening a
// recorded one (read, recover, and from 2026-10-19 take its writer lock).
func sessionOpenBenchmarks() {
    Benchmark("session/create") { benchmark in
        let directory = FileManager.default.temporaryDirectory.appending(path: "ask-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let paths = benchmark.scaledIterations.map { FilePath(directory.appending(path: "s\($0).jsonl").path) }
        benchmark.startMeasurement()
        for path in paths {
            let file = try SessionFile.create(at: path, durability: .none)
            blackHole(file.tree.count)
        }
        benchmark.stopMeasurement()
    }

    for size in [10, 1_000] {
        Benchmark("session/open \(size) entries") { benchmark in
            let directory = FileManager.default.temporaryDirectory.appending(path: "ask-bench-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = FilePath(directory.appending(path: "s.jsonl").path)
            do {
                var file = try SessionFile.create(at: path, durability: .none)
                for _ in 0 ..< size { try file.append(.assistant(String(repeating: "x", count: 400))) }
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                let file = try SessionFile.open(at: path, durability: .none)
                blackHole(file.tree.count)
            }
            benchmark.stopMeasurement()
        }
    }
}
