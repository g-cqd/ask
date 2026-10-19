import AskAI
import AskAgentCore
import Benchmark
import Foundation
import System

/// Answers instantly with a short text reply: what remains is ask's own per-turn work.
private struct InstantProvider: ModelProvider {
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (stream, continuation) = AsyncThrowingStream<ModelEvent, any Error>.makeStream()
        let events: [ModelEvent] = [
            .messageStarted(id: "m", model: "c", usage: TokenUsage(input: 1)), .blockStarted(index: 0, .text),
            .textDelta(index: 0, "Done."), .blockStopped(index: 0),
            .messageDelta(stopReason: .endTurn, usage: TokenUsage(output: 1)), .messageStopped
        ]
        for event in events { continuation.yield(event) }
        continuation.finish()
        return stream
    }
}

/// One whole turn (record the prompt, build context, encode nothing, assemble, record the reply) on sessions
/// of growing length, without flushing: ask's overhead per turn, which roadmap 0007's budget needs.
func loopBenchmarks(input: PromptQueue? = nil) {
    let loop = AgentLoop(
        provider: InstantProvider(), tools: try! ToolRegistry([]),
        settings: AgentSettings(model: "c", maximumTokens: 1_024, systemPrompt: ["You are ask."], maximumTurns: 4),
        context: ToolContext(workingDirectory: "/tmp"))
    for history in [0, 50, 500] {
        Benchmark("loop/one turn after \(history) turns\(input == nil ? "" : ", empty input")") { benchmark in
            let directory = FileManager.default.temporaryDirectory.appending(
                path: "ask-bench-loop-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = SessionRecorder(
                try SessionFile.create(at: FilePath(directory.appending(path: "s.jsonl").path), durability: .none))
            for turn in 0 ..< history {
                try file.append(.user("Step \(turn)."))
                try file.append(.assistant("Reply \(turn), with a sentence of ordinary length in it."))
            }
            benchmark.startMeasurement()
            for _ in benchmark.scaledIterations {
                try await loop.run("Next step.", in: file, input: input) { blackHole($0) }
            }
            benchmark.stopMeasurement()
        }
    }
}
