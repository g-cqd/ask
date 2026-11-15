import AemiJSON
import AskAI
import Foundation
import Synchronization
import Testing

@testable import AskAgentCore

/// A conversation several times the model's window (measured, diary 2026-11-15: 14.4 MB, 3,330,961 tokens, sent to a 1,000,000-token
/// window after a change of model): it is not sent when ask can tell, and its summary is made in parts that each fit.
@Suite("A conversation far longer than the window is compacted in parts that fit")
struct AgentLoopOversizedTests {
    private let harness = CompactionHarness()

    /// A server with a window of `window` tokens at four bytes a token: it refuses a longer request, summarises when asked to, and
    /// otherwise answers.
    private final class Windowed: ModelProvider {
        let window: Int
        let namesWindow: Bool
        private let seen = Mutex<(accepted: [ModelRequest], refused: Int)>(([], 0))

        init(window: Int, namesWindow: Bool = true) {
            self.window = window
            self.namesWindow = namesWindow
        }

        var refused: Int { seen.withLock { $0.refused } }
        /// The summary requests that were answered, in order.
        var summarised: [ModelRequest] { seen.withLock { $0.accepted }.filter(Self.asksForSummary) }

        static func asksForSummary(_ request: ModelRequest) -> Bool {
            request.messages.last?.blocks
                .contains { block in
                    if case .text(let text) = block { text.contains("about to be compacted") } else { false }
                } ?? false
        }

        func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
            let (stream, continuation) = AsyncThrowingStream<ModelEvent, any Error>.makeStream()
            guard RequestRewrite.textBytes(of: request) / 4 <= window else {
                seen.withLock { $0.refused += 1 }
                continuation.finish(throwing: ScriptedProvider.OverflowFailure(window: namesWindow ? window : nil))
                return stream
            }
            let count = seen.withLock {
                $0.accepted.append(request)
                return $0.accepted.count
            }
            let text = Self.asksForSummary(request) ? "SUMMARY \(count)" : "Done."
            let events: [ModelEvent] = [
                .messageStarted(id: "m", model: "x", usage: TokenUsage(input: 1)), .blockStarted(index: 0, .text),
                .textDelta(index: 0, text), .blockStopped(index: 0),
                .messageDelta(stopReason: .endTurn, usage: TokenUsage(output: 1)), .messageStopped
            ]
            events.forEach { continuation.yield($0) }
            continuation.finish()
            return stream
        }
    }

    /// A session of `rounds` tool calls, each with `inputBytes` of input and a 3,000-byte result: 120 KB at 40 rounds.
    private func session(rounds: Int = 40, inputBytes: Int = 2) throws -> SessionRecorder {
        let file = try harness.newFile()
        _ = try file.append(.user("The goal."))
        let input = try JSONObject(
            validating: Array(#"{"k":""#.utf8 + Array(repeating: 0x61, count: inputBytes) + #""}"#.utf8)
        )
        for round in 0 ..< rounds {
            let response = AssembledResponse(
                id: "m\(round)",
                model: "x",
                blocks: [.toolCall(id: "t\(round)", name: "bash", input: input)],
                stopReason: .toolUse,
                usage: TokenUsage(),
                unrecognized: []
            )
            _ = try file.append(.response(response))
            _ = try file.append(
                .toolResult(callID: "t\(round)", content: String(repeating: "x", count: 3_000), isError: false)
            )
        }
        return file
    }

    private func loop(_ provider: Windowed, knowing window: Int?) -> AgentLoop {
        var settings = AgentSettings(
            model: "x",
            maximumTokens: 1_024,
            systemPrompt: ["Be brief."],
            maximumTurns: 8,
            compactAtTokens: nil,
            keepRecentBytes: 1
        )
        settings.contextWindow = window
        return AgentLoop(
            provider: provider,
            tools: try! ToolRegistry([]),
            settings: settings,
            context: ToolContext(workingDirectory: harness.directory.path)
        )
    }

    /// The identifiers of the tool calls the answered summary requests carried, in order.
    private func summarisedCalls(_ provider: Windowed) -> [String] {
        provider.summarised.flatMap { request in
            request.messages.flatMap(\.blocks)
                .compactMap { block -> String? in
                    if case .toolCall(let id, _, _) = block { id } else { nil }
                }
        }
    }

    private func summary(_ file: SessionRecorder) -> String? {
        file.tree.entries.lazy
            .compactMap { entry -> String? in
                if case .compaction(let summary, _) = entry.payload { summary } else { nil }
            }
            .last
    }

    @Test func `a refused conversation three times the window is summarised in parts, each call in one part`()
        async throws
    {
        let file = try session()
        let provider = Windowed(window: 10_000)
        var events: [AgentEvent] = []
        try await loop(provider, knowing: nil).run("continue", in: file) { events.append($0) }
        #expect(events.last == .finished(.endTurn))
        #expect(provider.refused == 1, "only the request that showed the window")
        #expect(provider.summarised.count > 1)
        #expect(summarisedCalls(provider) == (0 ..< 40).map { "t\($0)" })
        #expect(summary(file) == "SUMMARY \(provider.summarised.count)", "the last part's summary carries the others")
        // Each part after the first opens with the summary of the parts before it.
        for (offset, request) in provider.summarised.enumerated().dropFirst() {
            #expect(request.messages.first?.blocks.first == .text(RequestContext.summaryPrefix + "SUMMARY \(offset)"))
        }
    }

    @Test func `with the window known, a conversation clearly longer than it is compacted without being sent`()
        async throws
    {
        let file = try session()
        let provider = Windowed(window: 10_000)
        try await loop(provider, knowing: 10_000).run("continue", in: file) { _ in }
        #expect(provider.refused == 0)
        #expect(harness.kinds(file).suffix(2) == ["compaction", "response"])
        #expect(summarisedCalls(provider) == (0 ..< 40).map { "t\($0)" })
    }

    @Test func `a part the server refuses is halved until it fits`() async throws {
        // No window known and none named: only refusals size the parts.
        let file = try session()
        let provider = Windowed(window: 10_000, namesWindow: false)
        try await loop(provider, knowing: nil).run("continue", in: file) { _ in }
        #expect(harness.kinds(file).suffix(2) == ["compaction", "response"])
        #expect(summarisedCalls(provider) == (0 ..< 40).map { "t\($0)" })
        // The request, the whole summary request, the older part whole (117 KB), then its half (58 KB); a quarter fits 40 KB.
        #expect(provider.refused == 4)
    }

    @Test func `one turn that cannot fit is recorded mechanically, and the parts after it are still summarised`()
        async throws
    {
        // A call whose input alone is 80 KB, twice the window: no summary request can hold its turn.
        let file = try session(rounds: 1, inputBytes: 80_000)
        for round in 1 ..< 4 {
            let input = try JSONObject(validating: Array("{}".utf8))
            let response = AssembledResponse(
                id: "m\(round)",
                model: "x",
                blocks: [.toolCall(id: "t\(round)", name: "bash", input: input)],
                stopReason: .toolUse,
                usage: TokenUsage(),
                unrecognized: []
            )
            _ = try file.append(.response(response))
            _ = try file.append(.toolResult(callID: "t\(round)", content: "small", isError: false))
        }
        let provider = Windowed(window: 10_000)
        try await loop(provider, knowing: 10_000).run("continue", in: file) { _ in }
        #expect(harness.kinds(file).suffix(2) == ["compaction", "response"])
        #expect(provider.refused == 0)
        #expect(summarisedCalls(provider) == ["t1", "t2", "t3"])
        let opening = try #require(provider.summarised.last?.messages.first?.blocks.first)
        guard case .text(let carried) = opening else {
            Issue.record("the part after the turn that did not fit does not open with a summary")
            return
        }
        #expect(carried.contains("SUMMARY 1"), "the summary of the part before the turn is kept")
        #expect(carried.contains(#"bash {"k":"aaa"#), "the turn is recorded by its call")
        #expect(carried.utf8.count < 8_000, "and not with its 80 KB of input")
    }
}
