internal import Foundation
internal import Testing

@testable import AskAI

/// Two connections of one provider can be two grants of ONE account: they then share that account's usage limits, and a user who
/// believes they are two accounts is misled (roadmap 0046; the owner's `work` and `claude-a` are exactly this). Identity is what the
/// stored credentials say: a Codex account id, a Claude account address.
struct ConnectionSharedAccountTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-shared-\(UUID().uuidString)")
    private var registry: ConnectionRegistry { ConnectionRegistry(directory: root.appending(path: "connections")) }
    private var defaultFile: CredentialFile { CredentialFile(url: root.appending(path: "credentials.json")) }

    private func codex(_ account: String, _ token: String = "t") -> CodexCredentials {
        CodexCredentials(accessToken: token, refreshToken: "r", expiresAt: 9, accountID: account)
    }

    private func claude(_ email: String) -> ClaudeCredentials {
        ClaudeCredentials(
            accessToken: "a", refreshToken: "r", expiresAt: 9, refreshExpiresAt: nil, accountEmail: email,
            organizationName: nil,
            scopes: "user:inference")
    }

    private func signIn(_ name: String, codex account: String) throws -> ConnectionRecord {
        let record = try registry.register(name: name, provider: .codex)
        try registry.saveCodex(codex(account), for: record)
        return record
    }

    @Test func `a connection alone holds its account alone`() throws {
        let work = try signIn("work", codex: "acct_1")
        #expect(try registry.connections(as: .codex("acct_1"), excluding: work).isEmpty)
        #expect(try registry.connections(as: .codex("acct_1")) == ["work"])
    }

    @Test func `two connections signed in as one account name each other`() throws {
        let work = try signIn("work", codex: "acct_1")
        let home = try signIn("home", codex: "acct_1")
        #expect(try registry.connections(as: .codex("acct_1"), excluding: work) == ["home"])
        #expect(try registry.connections(as: .codex("acct_1"), excluding: home) == ["work"])
        #expect(try registry.connections(as: .codex("acct_1")) == ["home", "work"])
    }

    @Test func `holders come back sorted by name whatever order they were registered in`() throws {
        for name in ["f", "e", "d", "c", "b", "a"] { _ = try signIn(name, codex: "acct_1") }
        #expect(try registry.connections(as: .codex("acct_1")) == ["a", "b", "c", "d", "e", "f"])
    }

    @Test func `different accounts do not share`() throws {
        let work = try signIn("work", codex: "acct_1")
        _ = try signIn("home", codex: "acct_2")
        #expect(try registry.connections(as: .codex("acct_1"), excluding: work).isEmpty)
    }

    @Test func `a Codex id and a Claude address are never mistaken for one another`() throws {
        _ = try signIn("work", codex: "same@example.com")
        let ant = try registry.register(name: "ant", provider: .anthropic)
        try registry.saveClaude(claude("same@example.com"), for: ant)
        #expect(try registry.connections(as: .claude("same@example.com")) == ["ant"])
        #expect(try registry.connections(as: .codex("same@example.com")) == ["work"])
    }

    @Test func `a Claude address matches whatever its letter case`() throws {
        let ant = try registry.register(name: "ant", provider: .anthropic)
        try registry.saveClaude(claude("Person@Example.com"), for: ant)
        #expect(try registry.connections(as: .claude("person@example.COM")) == ["ant"])
    }

    @Test func `a connection that was signed out or removed holds no account`() throws {
        let work = try signIn("work", codex: "acct_1")
        let home = try signIn("home", codex: "acct_1")
        let third = try signIn("third", codex: "acct_1")
        try registry.signOut(home)
        try registry.remove(third)
        #expect(try registry.connections(as: .codex("acct_1"), excluding: work).isEmpty)
    }

    @Test func `a damaged neighbour does not stop the answer`() throws {
        let work = try signIn("work", codex: "acct_1")
        let home = try signIn("home", codex: "acct_1")
        try Data("{broken".utf8).write(to: registry.credentials(for: home).url)
        #expect(try registry.connections(as: .codex("acct_1"), excluding: work).isEmpty)
        #expect(try registry.connections(as: .codex("acct_1")) == ["work"])
    }

    @Test func `the default sign-in is checked the same way`() throws {
        #expect(try !defaultFile.isSignedIn(as: .codex("acct_1")), "nothing stored")
        try defaultFile.saveCodex(codex("acct_1"))
        #expect(try defaultFile.isSignedIn(as: .codex("acct_1")))
        #expect(try !defaultFile.isSignedIn(as: .codex("acct_2")))
        #expect(try !defaultFile.isSignedIn(as: .claude("acct_1")), "another provider's record")
        try defaultFile.saveClaude(claude("Me@Example.com"))
        #expect(try defaultFile.isSignedIn(as: .claude("me@example.com")))
    }

    @Test func `the notice names every holder and says what sharing means`() {
        let none = AccountSharing(connections: [], defaultSignIn: false)
        #expect(none.notice == nil)
        let both = AccountSharing(connections: ["home", "work"], defaultSignIn: true)
        let text = both.notice ?? ""
        #expect(text.contains("home") && text.contains("work") && text.contains("default"))
        #expect(text.contains("usage limits"))
        #expect(AccountSharing(connections: [], defaultSignIn: true).notice?.contains("default") == true)
        #expect(AccountSharing(connections: ["work"], defaultSignIn: false).notice?.contains("default") == false)
    }

    @Test func `the one-line summary reads as part of a listing`() {
        #expect(AccountSharing(connections: [], defaultSignIn: false).summary == nil)
        #expect(AccountSharing(connections: [], defaultSignIn: true).summary == "same account as the default sign-in")
        #expect(
            AccountSharing(connections: ["work"], defaultSignIn: false).summary == "same account as connection 'work'")
        #expect(
            AccountSharing(connections: ["a", "b"], defaultSignIn: true).summary
                == "same account as the default sign-in, connection 'a' and connection 'b'")
    }
}
