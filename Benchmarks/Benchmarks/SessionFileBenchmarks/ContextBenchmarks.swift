import AskAI
import AskAgentCore
import Benchmark

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
