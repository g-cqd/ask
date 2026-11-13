internal import AemiSearch
internal import AskAI
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

    /// A compaction brings the search index up to date in the background (t209). On a long session that takes a while, and the task
    /// must not hold the session meanwhile: it works from what the session held at that moment.
    @Test func `a session left right after a compaction is released while its index is still being built`() async throws
    {
        let fixture = try await ConversationFixture()
        let conversation = fixture.conversation
        let first = try fixture.newSession()
        let line = String(repeating: "alpha beta gamma delta ", count: 40)
        for index in 0 ..< 4_000 { _ = try first.append(.user("\(index) \(line)")) }
        let path = first.path
        conversation.activateSession(first, update: fixture.update)
        weak let held = first
        conversation.deliver(.compacted(summary: "Summary.", usage: TokenUsage()), to: fixture.update)
        conversation.activateSession(nil, update: fixture.update)
        _ = consume first
        #expect(held == nil, "the indexing task does not hold the old recorder")
        #expect(ConversationFixture.isUnlocked(path))
    }

    @Test func `the index of a session left behind is dropped from memory, and made again when it is searched`()
        async throws
    {
        let fixture = try await ConversationFixture()
        let session = try fixture.newSession()
        _ = try session.append(.user("the cache key is the URL"))
        let search = SessionSearch.of(session: session.path)
        #expect(await search.search(SearchQuery("cache"), in: session).count == 1)
        fixture.conversation.activateSession(session, update: fixture.update)
        fixture.conversation.activateSession(nil, update: fixture.update)
        #expect(SessionSearch.of(session: session.path) !== search, "the one that was open is forgotten")
        #expect(await SessionSearch.of(session: session.path).search(SearchQuery("cache"), in: session).count == 1)
    }
}
