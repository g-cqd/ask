import AskAgentCore
import AskTUI
import Foundation
import Synchronization
import Testing

@testable import AskSession

/// The task list and the notes are a conversation's (ADR-0154): `ask serve` holds several conversations in one process, and one
/// kept for the process would have each write the other's.
@Suite("Each conversation keeps its own tasks and notes")
struct SessionListsTests {
    private func notices(_ fixture: ConversationFixture) -> [String] {
        fixture.updates.compactMap { update in
            if case .notice(let text, _) = update { text } else { nil }
        }
    }

    @Test func `a note added in one conversation is in its session's notes, and not in another's`() async throws {
        let first = try await ConversationFixture()
        let second = try await ConversationFixture()
        let firstSession = try first.conversation.recorder()
        // The second session starts after the first: one list for the process would now be following this one.
        let secondSession = try second.conversation.recorder()

        first.conversation.notes(arguments: "from the first", update: first.update)
        second.conversation.notes(arguments: "from the second", update: second.update)
        first.conversation.notes(command: "notes:all", arguments: "", update: first.update)
        second.conversation.notes(command: "notes:all", arguments: "", update: second.update)

        #expect(notices(first).last?.contains("from the first") == true)
        #expect(notices(first).last?.contains("from the second") == false)
        #expect(notices(second).last?.contains("from the second") == true)
        #expect(notices(second).last?.contains("from the first") == false)
        let firstFile = IdeaBoard.path(forSessionAt: firstSession.path, scope: .session)
        let secondFile = IdeaBoard.path(forSessionAt: secondSession.path, scope: .session)
        #expect(FileManager.default.fileExists(atPath: firstFile), "the first session's notes are in its own file")
        #expect(FileManager.default.fileExists(atPath: secondFile))
    }

    @Test func `a note typed before a conversation's first prompt waits for that conversation's session`() async throws
    {
        let waiting = try await ConversationFixture()
        let other = try await ConversationFixture()
        _ = try other.conversation.recorder()
        // The other conversation has a session; this one has none yet, and its note is held, not written to the other's.
        waiting.conversation.notes(arguments: "held", update: waiting.update)
        #expect(notices(waiting).last?.hasPrefix("Kept: it is saved to your notes when the session starts") == true)
        other.conversation.notes(command: "notes:all", arguments: "", update: other.update)
        #expect(notices(other).last?.contains("held") == false)
        _ = try waiting.conversation.recorder()
        waiting.conversation.saveHeldIdeas(update: waiting.update)
        #expect(notices(waiting).last?.hasPrefix("Saved the note typed before the session started") == true)
    }

    @Test func `the tools a conversation's loop is given write that conversation's lists`() async throws {
        let first = try await ConversationFixture()
        let second = try await ConversationFixture()
        #expect(
            first.conversation.loopHooks(first.conversation.current.withLock { $0.settings }).lists
                === first.conversation.lists
        )
        #expect(first.conversation.lists !== second.conversation.lists)
        #expect(first.conversation.lists.board !== second.conversation.lists.board)
    }
}
