import AemiIO
import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// Compaction: a session whose prompt passed the threshold, or filled the window, is summarised into a
/// `.compaction` entry that keeps the recent tail, and the run continues on the shorter context.
@Suite("Long sessions are compacted before they outgrow the context")
struct AgentLoopCompactionTests {
    private let harness = CompactionHarness()
    private func newFile() throws -> SessionRecorder { try harness.newFile() }
    private func loop(_ provider: ScriptedProvider, compactAt: Int?, keepRecentBytes: Int = 1) -> AgentLoop {
        harness.loop(provider, compactAt: compactAt, keepRecentBytes: keepRecentBytes)
    }
    private func kinds(_ file: SessionRecorder) -> [String] { harness.kinds(file) }
    private var directory: URL { harness.directory }

    @Test func `a prompt past the threshold is compacted before the next request, keeping the recent tail`()
        async throws
    {
        let file = try newFile()
        let provider = ScriptedProvider([.sized("First answer.", prompt: 150), .reply("SUMMARY"), .reply("Second.")])
        let loop = loop(provider, compactAt: 100)
        try await loop.run("one", in: file) { _ in }
        #expect(provider.requests.count == 1)
        var events: [AgentEvent] = []
        try await loop.run("two", in: file) { events.append($0) }
        #expect(kinds(file) == ["user", "response", "user", "compaction", "response"])
        guard case .compaction(let summary, let firstKept) = file.tree.entries[3].payload else { return }
        #expect(summary == "SUMMARY")
        #expect(firstKept == file.tree.entries[2].id)
        #expect(provider.requests.count == 3)
        #expect(provider.requests[1].messages.last?.blocks.last == .text(Compaction.instruction))
        let resumed = provider.requests[2].messages
        #expect(resumed.first?.blocks.first == .text(RequestContext.summaryPrefix + "SUMMARY"))
        #expect(!resumed.flatMap(\.blocks).contains(.text("First answer.")))
        #expect(events.contains { if case .compacted = $0 { true } else { false } })
        // The screen is told before the summary is asked for, so it can say "Compacting..." meanwhile (roadmap 0099).
        let began = try #require(events.firstIndex(of: .compacting))
        #expect(began < events.firstIndex { if case .compacted = $0 { true } else { false } }!)
        // The summary is ask's own request: it is not shown as the assistant speaking.
        #expect(!events.contains(.model(.textDelta(index: 0, "SUMMARY"))))
    }

    @Test func `below the threshold, or with compaction off, nothing is compacted`() async throws {
        // 150 prompt tokens plus a 1-token reply: 151 is due, 152 is not.
        for compactAt in [152, nil] {
            let file = try newFile()
            let provider = ScriptedProvider([.sized("a", prompt: 150), .reply("b")])
            let loop = loop(provider, compactAt: compactAt)
            try await loop.run("one", in: file) { _ in }
            try await loop.run("two", in: file) { _ in }
            #expect(kinds(file) == ["user", "response", "user", "response"])
            try FileManager.default.removeItem(at: directory)
        }
    }

    @Test func `a response stopped at the full context window is compacted and continued`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.windowFull("partial"), .reply("SUMMARY"), .reply("Done.")])
        var events: [AgentEvent] = []
        try await loop(provider, compactAt: nil).run("go", in: file) { events.append($0) }
        #expect(kinds(file) == ["user", "response", "user", "compaction", "response"])
        #expect(file.tree.entries[2].payload == .user(AgentLoop.contextFullPrompt))
        #expect(events.last == .finished(.endTurn))
    }

    @Test func `a large tool output in the part being summarised is clipped to its head and tail`() {
        let big = String(repeating: "a", count: 50_000) + "MIDDLE" + String(repeating: "z", count: 50_000)
        let clipped = Compaction.clipped(big, toBytes: 4_000)
        #expect(clipped.utf8.count < 4_200)
        #expect(clipped.hasPrefix("aaaa"))
        #expect(clipped.hasSuffix("zzzz"))
        #expect(!clipped.contains("MIDDLE"))
        #expect(clipped.contains("omitted"))
        #expect(Compaction.clipped("short", toBytes: 4_000) == "short")
    }

    @Test func `a summary that cannot be made leaves the session whole, says so, and the run goes on`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.sized("a", prompt: 150), .permanent, .reply("b")])
        let loop = loop(provider, compactAt: 100)
        try await loop.run("one", in: file) { _ in }
        var events: [AgentEvent] = []
        try await loop.run("two", in: file) { events.append($0) }
        #expect(kinds(file) == ["user", "response", "user", "response"])
        #expect(events.contains { if case .compactionFailed = $0 { true } else { false } })
    }

    @Test func `the size that triggers compaction is the newest response's since the last compaction`() throws {
        var tree = SessionTree()
        try tree.append(.user("one"))
        let big = AssembledResponse(
            id: "m", model: "x", blocks: [.text("a")], stopReason: .endTurn,
            usage: TokenUsage(input: 10, output: 5, cacheRead: 100, cacheCreation: 20), unrecognized: [])
        try tree.append(.response(big))
        #expect(Compaction.contextTokens(sinceCompactionIn: tree) == 135)
        let kept = try tree.append(.user("two"))
        try tree.append(.compaction(summary: "s", firstKept: kept))
        #expect(Compaction.contextTokens(sinceCompactionIn: tree) == nil)
    }

    @Test func `a conversation that fits the kept tail is never compacted and reports nothing`() async throws {
        // A small window drives the threshold to the floor, so compaction is "due" from the first response
        // (probed on the on-device model, diary 2026-10-28): with nothing before the tail, it is a no-op, not a
        // failure to announce on every turn.
        let file = try newFile()
        let provider = ScriptedProvider([.sized("First answer.", prompt: 150), .reply("Second.")])
        let loop = loop(provider, compactAt: 100, keepRecentBytes: 100_000)
        try await loop.run("one", in: file) { _ in }
        var events: [AgentEvent] = []
        try await loop.run("two", in: file) { events.append($0) }
        #expect(kinds(file) == ["user", "response", "user", "response"])
        #expect(!events.contains { if case .compactionFailed = $0 { true } else { false } })
        #expect(provider.requests.count == 2)
    }

    @Test func `a single turn that fills the tail on its own is skipped, not reported as failed`() async throws {
        // The tail's bytes are reached only at the branch's first entry, so nothing precedes the tail and
        // compaction cannot run; it is quietly skipped rather than announced as a failure every turn.
        let file = try newFile()
        let prompt = String(repeating: "x", count: 1_000)
        let provider = ScriptedProvider([
            .call(id: "t1", name: "nothing", input: "{}"), .reply("done."), .reply("second.")
        ])
        let loop = loop(provider, compactAt: 1, keepRecentBytes: 400)
        try await loop.run(prompt, in: file) { _ in }
        var events: [AgentEvent] = []
        try await loop.run("two", in: file) { events.append($0) }
        #expect(kinds(file).prefix(3) == ["user", "response", "result"])
        #expect(!events.contains { if case .compactionFailed = $0 { true } else { false } })
    }

    @Test func `an explicit compaction with nothing before the tail still says so`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.reply("First.")])
        let loop = loop(provider, compactAt: nil, keepRecentBytes: 100_000)
        try await loop.run("one", in: file) { _ in }
        var events: [AgentEvent] = []
        try await loop.compactNow(in: file) { events.append($0) }
        #expect(events.contains { if case .compactionFailed = $0 { true } else { false } })
        #expect(events.contains(.compacting), "a compaction that fails still began, and its end clears the status")
    }

    @Test func `the kept tail never starts at a tool result, which would orphan it from its call`() throws {
        let input = try JSONObject(validating: Array("{}".utf8))
        let call = AssembledResponse(
            id: "m", model: "x", blocks: [.toolCall(id: "t1", name: "bash", input: input)], stopReason: .toolUse,
            usage: TokenUsage(), unrecognized: [])
        let entries = [
            SessionPayload.user("start"), .response(call),
            .toolResult(callID: "t1", content: "0123456789", isError: false)
        ]
        .enumerated().map { SessionEntry(id: EntryID("e\($0.offset)"), parentID: nil, payload: $0.element) }
        // Ten bytes reach back to the tool result alone; the cut moves back to the call that made it.
        #expect(Compaction.cut(entries, keepingRecentBytes: 10) == 1)
        // Keeping everything leaves nothing to summarise.
        #expect(Compaction.cut(entries, keepingRecentBytes: 1_000) == nil)
    }
}
