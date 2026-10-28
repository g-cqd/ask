import AemiIO
import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// Fitting the context window: a request refused for its length, a reply cut off by a full window, a window learned
/// from either, and the limits that keep a conversation that cannot fit from looping (diary 14, measured on an 8k
/// llama.cpp server).
@Suite("The loop fits the conversation to the model's context window")
struct AgentLoopWindowTests {
    private let harness = CompactionHarness()
    private func newFile() throws -> SessionRecorder { try harness.newFile() }
    private func loop(_ provider: ScriptedProvider, compactAt: Int?, keepRecentBytes: Int = 1) -> AgentLoop {
        harness.loop(provider, compactAt: compactAt, keepRecentBytes: keepRecentBytes)
    }
    private func kinds(_ file: SessionRecorder) -> [String] { harness.kinds(file) }
    private var directory: URL { harness.directory }

    @Test func `a request refused for its length is compacted and sent again, not retried as it was`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: "{}"), .overflow, .reply("SUMMARY"), .reply("Done.")
        ])
        var events: [AgentEvent] = []
        try await loop(provider, compactAt: nil).run("go", in: file) { events.append($0) }
        #expect(kinds(file) == ["user", "response", "result", "compaction", "response"])
        #expect(provider.requests.count == 4)
        #expect(events.last == .finished(.endTurn))
    }

    @Test func `a second overflow right after compacting ends the run, rather than looping`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: "{}"), .overflow, .reply("SUMMARY"), .overflow
        ])
        await #expect(throws: AgentError.contextOverflow("request exceeds the available context size")) {
            try await loop(provider, compactAt: nil).run("go", in: file) { _ in }
        }
        #expect(provider.requests.count == 4)
    }

    @Test func `an overflow compacts even when the kept tail would have covered everything`() async throws {
        // Measured on an 8k local server (diary 14): the default tail held the whole conversation, so the compaction
        // the refusal called for found nothing to summarise, and the run ended.
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: "{}"), .overflow, .reply("SUMMARY"), .reply("Done.")
        ])
        try await loop(provider, compactAt: nil, keepRecentBytes: 1_000_000).run("go", in: file) { _ in }
        #expect(kinds(file) == ["user", "response", "result", "compaction", "response"])
    }

    @Test func `a summary request too long for the window is sent again with only the part being replaced`()
        async throws
    {
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: "{}"), .overflow, .overflow, .reply("SUMMARY"), .reply("Done.")
        ])
        try await loop(provider, compactAt: nil).run("go", in: file) { _ in }
        #expect(kinds(file) == ["user", "response", "result", "compaction", "response"])
        let full = provider.requests[2].messages.count
        let reduced = provider.requests[3].messages.count
        #expect(reduced < full, "the second summary request carries only the older part (\(reduced) of \(full))")
    }

    @Test func `a model that writes no summary is replaced by a record that keeps the user's words, not its musings`()
        async throws
    {
        // Using the reasoning as the summary was tried and refuted on a real 8k server (diary 14): the musings replaced
        // the goal, and the model went on to invent another task.
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: #"{"path":"part1.txt"}"#),
            .call(id: "t2", name: "missing", input: #"{"path":"part2.txt"}"#), .overflow,
            .thinkingOnly("Wait, let me reconsider."), .reply("Done.")
        ])
        try await loop(provider, compactAt: nil).run("Report the six codes.", in: file) { _ in }
        // The first call is in the replaced part; the second is kept word for word.
        guard
            let summary = file.tree.entries.lazy
                .compactMap({ entry -> String? in
                    if case .compaction(let summary, _) = entry.payload { summary } else { nil }
                })
                .first
        else {
            Issue.record("no compaction: \(kinds(file))")
            return
        }
        #expect(summary.contains("Report the six codes."))
        #expect(summary.contains("missing"))
        #expect(summary.contains("part1.txt"))
        #expect(!summary.contains("reconsider"))
    }

    @Test func `with a window known, one turn's tool outputs together fit it`() async throws {
        let file = try newFile()
        let big = String(repeating: "x", count: 40_000) + " FINAL FACT: GOLD"
        let provider = ScriptedProvider([
            .calls([("a", "big", "{}"), ("b", "big", "{}"), ("c", "big", "{}"), ("d", "big", "{}")]), .reply("Done.")
        ])
        let loop = AgentLoop(
            provider: provider, tools: try ToolRegistry([Fixed(name: "big", output: big)]),
            settings: AgentSettings(
                model: "m", maximumTokens: 1_024, systemPrompt: [], maximumTurns: 4, compactAtTokens: nil,
                keepRecentBytes: 1, toolOutputBytes: 8_192),
            context: ToolContext(workingDirectory: directory.path))
        try await loop.run("go", in: file) { _ in }
        let results = file.tree.entries.compactMap { entry -> String? in
            if case .toolResult(_, let content, _, _) = entry.payload { content } else { nil }
        }
        #expect(results.count == 4)
        #expect(results.reduce(0) { $0 + $1.utf8.count } <= 8_192 + 4 * 120)
        #expect(results.allSatisfy { $0.hasSuffix("FINAL FACT: GOLD") }, "the end of each output survives")
    }

    @Test func `a reply cut for length long before its output budget means the context is full, so it is compacted`()
        async throws
    {
        // Measured on an 8k llama.cpp server (diary 14): asked for 16k output tokens, it stopped when its context
        // filled and said `length`, and asking it to continue failed the same way six times.
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: "{}"), .contextExhausted("partial"), .reply("SUMMARY"),
            .reply("Done.")
        ])
        var events: [AgentEvent] = []
        try await loop(provider, compactAt: nil).run("go", in: file) { events.append($0) }
        #expect(kinds(file) == ["user", "response", "result", "response", "user", "compaction", "response"])
        #expect(file.tree.entries[4].payload == .user(AgentLoop.contextFullPrompt))
        #expect(!events.contains(.continuedAtOutputLimit))
    }

    @Test func `a window learned from a reply it cut off sizes every later request to fit`() async throws {
        // The window filled at 3,000 prompt and 500 output tokens: a 3,500-token window, measured the way llama.cpp
        // showed it (diary 14: prompt plus cached plus output came to exactly its 8,192).
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: "{}"), .contextExhausted("partial", prompt: 3_000, output: 500),
            .reply("SUMMARY"), .reply("Done.")
        ])
        try await loop(provider, compactAt: nil, keepRecentBytes: 1_000_000).run("go", in: file) { _ in }
        #expect(provider.requests.first?.maxTokens == 1_024)
        #expect(provider.requests.last?.maxTokens == 875, "a quarter of the learned 3,500-token window")
    }

    @Test func `a refusal that names the window sizes every later request to it`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "missing", input: "{}"), .overflowNaming(window: 4_000), .reply("SUMMARY"),
            .reply("Done.")
        ])
        try await loop(provider, compactAt: nil).run("go", in: file) { _ in }
        #expect(provider.requests.first?.maxTokens == 1_024)
        #expect(provider.requests.last?.maxTokens == 1_000, "a quarter of the named 4,000-token window")
    }

    @Test func `compacting that never makes room ends the run instead of looping`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider(
            [.call(id: "t1", name: "missing", input: "{}")]
                + Array(
                    repeating: [.contextExhausted("partial", prompt: 3_000, output: 500), .reply("SUMMARY")], count: 5
                )
                .flatMap { $0 })
        await #expect(throws: AgentError.self) {
            try await loop(provider, compactAt: nil).run("go", in: file) { _ in }
        }
        // The first request, then each allowed compaction (a reply that filled the window plus its summary), then the
        // fill that stops the run.
        #expect(provider.requests.count == 1 + 2 * AgentLoop.fullWindowCompactionsBeforeGivingUp + 1)
    }

    /// A tool that always answers with the same output.
    private struct Fixed: Tool {
        let name: String
        let output: String
        var definition: ToolDefinition {
            ToolDefinition(name: name, description: name) { ToolProperty.string("x").optional }
        }
        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput { ToolOutput(output) }
    }
}
