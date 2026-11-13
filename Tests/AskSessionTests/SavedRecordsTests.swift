internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskSession

/// What the conversation keeps beside its messages is said when it cannot be saved (roadmap 0230): a failed write is never dropped.
@Suite("A record or a list that cannot be saved is said to the person", .timeLimit(.minutes(1)))
struct SavedRecordsTests {
    private func notices(_ fixture: ConversationFixture) -> [String] {
        fixture.updates.compactMap { update in
            if case .notice(let text, isError: true) = update { text } else { nil }
        }
    }

    @Test func `a fork whose task list cannot be copied still stands, and the person is told`() async throws {
        let fixture = try await ConversationFixture()
        fixture.conversation.approvals.withLock { $0.ask = fixture.update }
        let original = try fixture.newSession()
        _ = try original.append(.user("plan the work"))
        // A list the fork cannot read: the copy fails.
        let list = TaskBoard.path(forSessionAt: original.path, scope: .session)
        try Data("[]".utf8).write(to: URL(fileURLWithPath: list))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: list)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: list) }

        let fork = try fixture.conversation.forked(original, upTo: original.tree.leaf)
        #expect(fork.tree.entries.count == original.tree.entries.count, "the fork is made")
        #expect(notices(fixture).contains { $0.hasPrefix("The fork has no copy of the task list") })
    }

    @Test func `a thread record that is saved says nothing`() async throws {
        let fixture = try await ConversationFixture()
        fixture.conversation.approvals.withLock { $0.ask = fixture.update }
        let session = try fixture.newSession()
        fixture.conversation.saveThreadRecord(.renamed("thread-1", to: "Parser"), in: session, as: "the thread's name")
        fixture.conversation.saveThreadRecord(.renamed("thread-1", to: "Parser"), in: nil, as: "the thread's name")
        #expect(notices(fixture).isEmpty)
    }

    /// The fixture's files are its own: a conversation under test never reads or writes the person's configuration.
    @Test func `the fixture's credentials and connections are under its own folder`() async throws {
        let fixture = try await ConversationFixture()
        #expect(CredentialFile.standard(environment: fixture.environment).url.path.hasPrefix(fixture.root.path))
        #expect(askConfigDirectory(environment: fixture.environment).hasPrefix(fixture.root.path))
    }
}
