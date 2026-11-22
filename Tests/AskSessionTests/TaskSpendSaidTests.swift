internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization
internal import Testing

@testable import AskSession

/// A task made done says what the session spent while it was in progress (roadmap 0239): once each time it is done, not for the
/// tasks already done when the list was opened, and not for one never started.
@Suite("A task made done says what it cost")
struct TaskSpendSaidTests {
    /// The moments, in milliseconds: before and after every entry the test records, so a task's span is not left to the clock.
    private static let before = 1_000_000, after = 9_000_000_000_000

    private static func change(_ fixture: ConversationFixture, _ edits: [TaskEdit], _ moment: Int) throws {
        _ = try fixture.conversation.lists.board.update { list in
            let plan = try TaskPlanner.plan(edits, on: list, at: moment / 1_000, precisely: moment)
            return (plan.change, ())
        }
    }

    private static func said(_ fixture: ConversationFixture) -> [String] {
        fixture.updates.compactMap { update in
            if case .notice(let text, _) = update, text.contains(" done: ") { return text }
            return nil
        }
    }

    private static let response = AssembledResponse(
        id: "r",
        model: "m",
        blocks: [],
        stopReason: nil,
        usage: TokenUsage(input: 5, output: 7),
        unrecognized: []
    )

    @Test func `once for each time a task is done, never for one done before, nor one never started`() async throws {
        let fixture = try await ConversationFixture()
        let recorder = try fixture.newSession()
        fixture.conversation.session.withLock { $0 = recorder }
        _ = fixture.conversation.lists.follow(recorder, scope: .session)
        try Self.change(
            fixture,
            [.add(TaskDraft(title: "old", state: .inProgress)), .add(TaskDraft(title: "skip"))],
            Self.before
        )
        try recorder.append(.response(Self.response))
        try Self.change(fixture, [.state([.id(1)], .done)], Self.after)
        // What is already done when the list is followed was said before, or never will be.
        _ = fixture.conversation.lists.follow(recorder, scope: .session)
        try Self.change(fixture, [.add(TaskDraft(title: "new", state: .inProgress))], Self.before)
        try recorder.append(.user("go"))
        try Self.change(fixture, [.state([.id(3), .id(2)], .done)], Self.after)
        fixture.conversation.sayTaskSpend(update: fixture.update)
        fixture.conversation.sayTaskSpend(update: fixture.update)
        let said = Self.said(fixture)
        #expect(said.count == 1, "\(said)")
        #expect(
            said.first?.hasPrefix("t3 done: 1 request · ↑5 ↓7") == true,
            "t1 was done when the list was followed: \(said)"
        )
        try Self.change(fixture, [.state([.id(3)], .inProgress)], Self.before)
        try Self.change(fixture, [.state([.id(3)], .done)], Self.after + 1)
        fixture.conversation.sayTaskSpend(update: fixture.update)
        #expect(Self.said(fixture).count == 2, "done again, said again")
    }
}
