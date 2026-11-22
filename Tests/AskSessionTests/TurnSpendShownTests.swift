internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Testing

@testable import AskSession

/// A turn's cost, read from the session file when the turn ends (roadmap 0239): the entries after the leaf the turn began at, and
/// nothing said for a turn that spent nothing.
@Suite("A turn's cost is read from the session when it ends")
struct TurnSpendShownTests {
    private static func response(_ usage: TokenUsage) -> SessionPayload {
        .response(AssembledResponse(id: "r", model: "m", blocks: [], stopReason: nil, usage: usage, unrecognized: []))
    }

    @Test func `the turn's entries only, not the turn before it`() async throws {
        let fixture = try await ConversationFixture()
        let recorder = try fixture.newSession()
        try recorder.append(.user("earlier"))
        try recorder.append(Self.response(TokenUsage(input: 1_000, output: 1_000)))
        let start = recorder.tree.leaf
        try recorder.append(.user("go"))
        try recorder.append(Self.response(TokenUsage(input: 100, output: 20, cacheRead: 2_000)))
        try recorder.append(.toolResult(callID: "1", content: "ok", isError: false))
        try recorder.append(Self.response(TokenUsage(input: 50, output: 30)))
        fixture.conversation.showTurnSpend(in: recorder, since: start, update: fixture.update)
        let shown = fixture.updates.compactMap { update -> TurnSpend? in
            if case .turnSpent(let spend) = update { return spend }
            return nil
        }
        #expect(shown.count == 1)
        #expect(shown.first?.requests == 2 && shown.first?.toolCalls == 1)
        #expect(shown.first?.tokens == "↑2.1k ↓50", "the earlier turn's 1,000 tokens each way are not counted")
        #expect(shown.first?.seconds != nil, "written now, so timed")
    }

    @Test func `a turn that spent nothing says nothing`() async throws {
        let fixture = try await ConversationFixture()
        let recorder = try fixture.newSession()
        try recorder.append(.user("go"))
        fixture.conversation.showTurnSpend(in: recorder, since: recorder.tree.leaf, update: fixture.update)
        #expect(fixture.updates.isEmpty)
    }
}
