internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization
internal import Testing

@testable import AskSession

/// After a compaction, a line compares the work it summarised with the stretch before (roadmap 0239): the first says its own only.
@Suite("A compaction says what the work it summarised cost, beside the stretch before")
struct CompactionSpendSaidTests {
    private static func response(_ output: Int) -> SessionPayload {
        .response(
            AssembledResponse(
                id: "r",
                model: "m",
                blocks: [],
                stopReason: nil,
                usage: TokenUsage(output: output),
                unrecognized: []
            )
        )
    }

    private static func said(_ fixture: ConversationFixture) -> [String] {
        fixture.updates.compactMap { update in
            if case .notice(let text, _) = update, text.hasPrefix("Worked ") { return text }
            return nil
        }
    }

    @Test func `the first compaction says its stretch; the next compares it with the one before`() async throws {
        let fixture = try await ConversationFixture()
        let recorder = try fixture.newSession()
        fixture.conversation.session.withLock { $0 = recorder }
        let kept = try recorder.append(.user("a"))
        try recorder.append(Self.response(10))
        try recorder.append(.toolResult(callID: "1", content: "", isError: false))
        try recorder.append(Self.response(20))
        try recorder.append(.compaction(summary: "s1", firstKept: kept))
        fixture.conversation.sayCompactionSpend(update: fixture.update)
        #expect(
            Self.said(fixture).last?.hasPrefix("Worked before this compaction: 2 requests, 1 tool · ↓30 · ") == true
        )
        try recorder.append(.user("b"))
        try recorder.append(Self.response(400))
        try recorder.append(.compaction(summary: "s2", firstKept: kept))
        fixture.conversation.sayCompactionSpend(update: fixture.update)
        let second = Self.said(fixture).last ?? ""
        #expect(second.hasPrefix("Worked since the previous compaction: 1 request · ↓400 · "), "\(second)")
        #expect(second.contains("; the stretch before: 2 requests, 1 tool · ↓30"), "\(second)")
        try recorder.append(.compaction(summary: "s3, nothing done since", firstKept: kept))
        fixture.conversation.sayCompactionSpend(update: fixture.update)
        #expect(Self.said(fixture).count == 2, "a stretch that spent nothing says nothing")
    }
}
