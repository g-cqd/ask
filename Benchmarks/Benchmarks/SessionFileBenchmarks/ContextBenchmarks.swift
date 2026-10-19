import AskAI
import AskAgentCore
import AskTools
import Benchmark
import Foundation

/// Builds request messages from a session's context, which happens on every request over the whole history.
func contextBenchmarks() {
    for turns in [50, 500] {
        var tree = SessionTree()
        let input = try! JSONObject(validating: Array(#"{"path": "Sources/AskAI/SSEDecoder.swift"}"#.utf8))
        let result = String(repeating: "let value = compute(input) // a line of a file that was read\n", count: 34)
        for turn in 0 ..< turns {
            try! tree.append(.user("Step \(turn): read the decoder."))
            try! tree.append(
                .response(
                    AssembledResponse(
                        id: "m\(turn)", model: "c",
                        blocks: [.text("Reading."), .toolCall(id: "t\(turn)", name: "read", input: input)],
                        stopReason: .toolUse, usage: TokenUsage(), unrecognized: [])))
            try! tree.append(.toolResult(callID: "t\(turn)", content: result, isError: false))
        }
        let context = tree.context()
        Benchmark("context/build \(turns) turns") { benchmark in
            for _ in benchmark.scaledIterations { blackHole(RequestContext(context)) }
        }
    }
}

/// Caps a large tool output, which happens to every output a tool returns.
func capBenchmarks() {
    let manyLines = String(repeating: "a build log line that says something about a file and a target\n", count: 16_384)
    let oneLine = String(repeating: "x", count: 1 << 20)
    Benchmark("cap/1 MiB in 16384 lines") { benchmark in
        for _ in benchmark.scaledIterations { blackHole(OutputCap.standard.apply(manyLines)) }
    }
    Benchmark("cap/1 MiB on one line") { benchmark in
        for _ in benchmark.scaledIterations { blackHole(OutputCap.standard.apply(oneLine)) }
    }
}

/// read and edit on a 1 MiB source file: the per-call cost of the file tools.
func fileToolBenchmarks() {
    let directory = FileManager.default.temporaryDirectory.appending(path: "ask-bench-tools-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source =
        String(repeating: "    let value = compute(input) // a line of Swift source\n", count: 19_000) + "MARKER\n"
    try! Data(source.utf8).write(to: directory.appending(path: "big.swift"))
    let context = ToolContext(workingDirectory: directory.path)
    let read = try! JSONObject(validating: Array(#"{"path":"big.swift"}"#.utf8))
    Benchmark("tools/read 1 MiB") { benchmark in
        for _ in benchmark.scaledIterations { blackHole(await ReadTool().run(read, in: context)) }
    }
    let flip = [
        try! JSONObject(validating: Array(#"{"path":"big.swift","old_text":"MARKER","new_text":"MARKED"}"#.utf8)),
        try! JSONObject(validating: Array(#"{"path":"big.swift","old_text":"MARKED","new_text":"MARKER"}"#.utf8))
    ]
    Benchmark("tools/edit 1 MiB, one match") { benchmark in
        for iteration in benchmark.scaledIterations {
            blackHole(await EditTool().run(flip[iteration % 2], in: context))
        }
    }
}

/// One trivial bash call, spawn to exit: the fixed cost every command pays.
func bashBenchmarks() {
    let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)
    let echo = try! JSONObject(validating: Array(#"{"command":"echo hi"}"#.utf8))
    Benchmark("tools/bash echo", configuration: .init(maxDuration: .seconds(3), maxIterations: 300)) { benchmark in
        for _ in benchmark.scaledIterations { blackHole(await BashTool().run(echo, in: context)) }
    }
    // The same call under ask's default protections: what the sandbox adds to every command (ADR-0035).
    let home = NSHomeDirectory()
    let protected = ToolContext(
        workingDirectory: FileManager.default.temporaryDirectory.path,
        sandbox: .standard(
            home: home, configDirectory: home + "/.config/ask", stateDirectory: home + "/.local/state/ask"))
    Benchmark("tools/bash echo sandboxed", configuration: .init(maxDuration: .seconds(3), maxIterations: 300)) {
        benchmark in
        for _ in benchmark.scaledIterations { blackHole(await BashTool().run(echo, in: protected)) }
    }
}
