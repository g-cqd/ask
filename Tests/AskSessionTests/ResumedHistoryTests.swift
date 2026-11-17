internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Testing

@testable import AskSession

/// What the screen shows of a resumed session (roadmap 0238, ADR-0165): what a request still reads, and a line saying how much came
/// before, rather than every entry the session holds.
@Suite("A resumed session shows the conversation since its last compaction, and says what it leaves out")
struct ResumedHistoryTests {
    private func notices(_ updates: [ConversationUpdate]) -> [String] {
        updates.compactMap { update in
            if case .notice(let text, _) = update { text } else { nil }
        }
    }

    /// Three turns, a compaction keeping the last of them, and one turn after; the conversation holding it.
    private func compacted() async throws -> ConversationFixture {
        let fixture = try await ConversationFixture()
        let session = try fixture.newSession()
        var kept: EntryID?
        for turn in 1 ... 3 {
            let prompt = try session.append(.user("prompt \(turn)"))
            if turn == 3 { kept = prompt }
            _ = try session.append(.assistant("answer \(turn)"))
        }
        _ = try session.append(.compaction(summary: "the first turns", firstKept: try #require(kept)))
        _ = try session.append(.user("after"))
        fixture.conversation.activateSession(session, update: fixture.update)
        return fixture
    }

    @Test func `entries before the last compaction's first kept one are left out, and said`() async throws {
        let fixture = try await compacted()
        let updates = fixture.conversation.history()
        let said = notices(updates)
        #expect(said.count == 1 && said[0].contains("since its last compaction; 4 earlier entries"), "\(said)")
        #expect(said[0].contains("/search") && said[0].contains("/rewind"))
        let text = "\(updates)"
        #expect(
            text.contains("prompt 3") && text.contains("after") && !text.contains("prompt 1")
                && !text.contains("answer 2")
        )
    }

    @Test func `a client that is sent the whole of a session is sent all of it, and told nothing of leaving out`()
        async throws
    {
        let fixture = try await compacted()
        let updates = fixture.conversation.history(whole: true)
        #expect(notices(updates).isEmpty)
        #expect("\(updates)".contains("prompt 1"))
    }

    @Test func `a session never compacted is shown whole, with no line about it`() async throws {
        let fixture = try await ConversationFixture()
        let session = try fixture.newSession()
        _ = try session.append(.user("prompt 1"))
        _ = try session.append(.assistant("answer 1"))
        fixture.conversation.activateSession(session, update: fixture.update)
        let updates = fixture.conversation.history()
        #expect(notices(updates).isEmpty)
        #expect("\(updates)".contains("prompt 1"))
    }
}
