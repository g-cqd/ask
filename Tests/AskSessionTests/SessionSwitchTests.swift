internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskSession

/// Leaving a session lets it go at once (ADR-0149, roadmap 0229): `/new`, fork and resume all pass through `activateSession`, after
/// which nothing of the conversation may hold the old recorder, so its writer lock is free for another ask. The defect of 2026-11-13
/// was a naming task that held it while a model was asked.
@Suite("A session switched away from is released at once", .timeLimit(.minutes(1)))
struct SessionSwitchTests {
    @Test func `the old session's lock is free at once, even while its name is being asked for`() async throws {
        let fixture = try await ConversationFixture()
        let conversation = fixture.conversation
        let first = try fixture.newSession()
        _ = try first.append(.user("build the parser"))
        let path = first.path
        conversation.activateSession(first, update: fixture.update)
        #expect(!ConversationFixture.isUnlocked(path), "the open session holds its lock")

        // A namer that says it was asked, then does not answer until told to: the naming task is alive across the switch.
        let (answers, release) = AsyncStream.makeStream(of: String?.self)
        let (asked, wasAsked) = AsyncStream.makeStream(of: Void.self)
        conversation.namer.withLock {
            $0 = { _ in
                wasAsked.yield()
                for await answer in answers { return answer }
                return nil
            }
        }
        conversation.nameConversation(startingWith: "build the parser", update: fixture.update)
        var waiting = asked.makeAsyncIterator()
        await waiting.next()
        weak let held = first
        conversation.activateSession(nil, update: fixture.update)
        _ = consume first
        // Checked while the name is still being asked for: that is when the defect held the session.
        #expect(held == nil, "nothing holds the old recorder")
        #expect(ConversationFixture.isUnlocked(path), "its lock is released")
        #expect(conversation.session.withLock { $0 } == nil)
        release.yield("Parser work")
        release.finish()
    }

    @Test func `a session that stays is named by what the namer answers`() async throws {
        let fixture = try await ConversationFixture()
        let session = try fixture.newSession()
        _ = try session.append(.user("build the parser"))
        fixture.conversation.activateSession(session, update: fixture.update)
        let (named, done) = AsyncStream.makeStream(of: String.self)
        fixture.conversation.namer.withLock { $0 = { _ in "Parser work" } }
        fixture.conversation.nameConversation(startingWith: "build the parser") { update in
            if case .conversationName(let name) = update { done.yield(name ?? "") }
        }
        var names = named.makeAsyncIterator()
        #expect(await names.next() == "Parser work")
    }
}
