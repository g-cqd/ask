internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Synchronization
internal import Testing

@testable import AskSession

/// Owner, 2026-11-26: a thread may work with a model of its own, chosen with `/model` in its lane; main keeps its model, and the
/// thread's lane names the model that answers there.
@Suite("/model in a thread's lane gives that thread its own model, and says which")
struct ThreadModelTests {
    private func thread(_ fixture: ConversationFixture) throws -> String {
        fixture.conversation.threads.add(prompt: "look", recorder: try fixture.newSession())
    }

    private func notices(_ fixture: ConversationFixture, in id: String) -> [String] {
        fixture.updates.compactMap { update in
            guard case .thread(id, .notice(let text, _)) = update else { return nil }
            return text
        }
    }

    @Test func `a model chosen in a thread's lane is the thread's alone, and its lane is told which`() async throws {
        let fixture = try await ConversationFixture()
        let id = try thread(fixture)
        await fixture.conversation.threadModel(id, arguments: "claude-other-2", update: fixture.update)
        #expect(fixture.conversation.threads.thread(id)?.model == "claude-other-2")
        #expect(notices(fixture, in: id).last?.contains("main keeps its model") == true)
        #expect(
            fixture.updates.contains {
                if case .thread(id, .label(let text)) = $0 { text.contains("claude-other-2") } else { false }
            }
        )
        #expect(
            !fixture.updates.contains { if case .label = $0 { true } else { false } },
            "main's label is not touched"
        )
    }

    @Test func `reset gives the thread back the conversation's model, and /model alone says which it works with`()
        async throws
    {
        let fixture = try await ConversationFixture()
        let id = try thread(fixture)
        await fixture.conversation.threadModel(id, arguments: "claude-other-2", update: fixture.update)
        await fixture.conversation.threadModel(id, arguments: "reset", update: fixture.update)
        #expect(fixture.conversation.threads.thread(id)?.model == nil)
        await fixture.conversation.threadModel(id, arguments: "", update: fixture.update)
        #expect(notices(fixture, in: id).last?.contains("claude-test-1") == true)
    }

    @Test func `the /model list marks the model of the thread whose lane is shown, and main's outside it`() async throws
    {
        let fixture = try await ConversationFixture()
        let id = try thread(fixture)
        await fixture.conversation.threadModel(id, arguments: "claude-other-2", update: fixture.update)
        #expect(await fixture.conversation.focusedThreadModel() == nil, "main's lane is shown")
        fixture.conversation.laneShown(id)
        #expect(await fixture.conversation.focusedThreadModel()?.model == "claude-other-2")
        fixture.conversation.laneShown(nil)
        #expect(await fixture.conversation.focusedThreadModel() == nil)
    }

    @Test func `a thread's own model is recorded in main's session, and comes back with it`() async throws {
        let fixture = try await ConversationFixture()
        let main = try fixture.newSession()
        _ = try main.append(.user("start"))
        fixture.conversation.session.withLock { $0 = main }
        let id = try Self.setUpThread(in: fixture, main: main)
        // The thread, back from main's records as a resume brings it, holding its own session.
        _ = fixture.conversation.restoreThreads()
        await fixture.conversation.threadModel(id, arguments: "claude-other-2", update: fixture.update)
        #expect(main.tree.threads.contains(.model(id, "claude-other-2")))
        // As a resume does: the table emptied, its sessions let go, then rebuilt from main's records.
        _ = fixture.conversation.restoreThreads()
        #expect(fixture.conversation.threads.thread(id)?.model == "claude-other-2")
        await fixture.conversation.threadModel(id, arguments: "reset", update: fixture.update)
        _ = fixture.conversation.restoreThreads()
        #expect(fixture.conversation.threads.thread(id)?.model == nil, "a reset is kept too")
    }

    /// A thread set up as starting one does, without running it; its session is closed once recorded, so a restore can open it.
    private static func setUpThread(in fixture: ConversationFixture, main: SessionRecorder) throws -> String {
        let path: String
        do {
            let recorder = try fixture.newSession()
            path = recorder.path
            _ = fixture.conversation.threads.add(prompt: "look", recorder: recorder)
        }
        let id = fixture.conversation.threads.runners.last?.id ?? "thread-1"
        try main.recordThread(.started(id, parent: nil, prompt: "look", file: path, at: main.tree.leaf))
        fixture.conversation.threads.reset()
        return id
    }
}
