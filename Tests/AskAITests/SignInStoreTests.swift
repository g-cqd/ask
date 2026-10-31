internal import Foundation
internal import Testing

@testable import AskAI

/// The whole store step: a second account is saved beside the first, and the first is untouched.
struct SignInStoreTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-store-\(UUID().uuidString)")
    private var registry: ConnectionRegistry { ConnectionRegistry(directory: root.appending(path: "connections")) }
    private var defaultFile: CredentialFile { CredentialFile(url: root.appending(path: "credentials.json")) }

    private func codex(_ account: String, _ token: String) -> CodexCredentials {
        CodexCredentials(accessToken: token, refreshToken: "r", expiresAt: 9, accountID: account)
    }

    private func claude(_ email: String, _ token: String) -> ClaudeCredentials {
        ClaudeCredentials(
            accessToken: token, refreshToken: "r", expiresAt: 9, refreshExpiresAt: nil, accountEmail: email,
            organizationName: nil, scopes: "user:inference")
    }

    @Test func `a second Codex account is a new connection and the default keeps the first`() throws {
        #expect(
            try registry.storeSignIn(.codex(codex("acct_1", "one")), defaultFile: defaultFile, replace: false)
                == .defaultSignIn
        )
        #expect(
            try registry.storeSignIn(.codex(codex("acct_2", "two")), defaultFile: defaultFile, replace: false)
                == .newConnection("codex-2"))
        #expect(try defaultFile.loadCodex()?.accessToken == "one")
        let added = try #require(try registry.list().records.first { $0.name == "codex-2" })
        #expect(added.provider == .codex)
        #expect(try registry.credentials(for: added).loadCodex(connection: added)?.accessToken == "two")
    }

    @Test func `signing in again to a connection's account refreshes that connection`() throws {
        _ = try registry.storeSignIn(.codex(codex("acct_1", "one")), defaultFile: defaultFile, replace: false)
        _ = try registry.storeSignIn(.codex(codex("acct_2", "two")), defaultFile: defaultFile, replace: false)
        #expect(
            try registry.storeSignIn(.codex(codex("acct_2", "new")), defaultFile: defaultFile, replace: false)
                == .connection("codex-2"))
        let added = try #require(try registry.list().records.first { $0.name == "codex-2" })
        #expect(try registry.credentials(for: added).loadCodex(connection: added)?.accessToken == "new")
        #expect(try registry.list().records.count == 1)
    }

    @Test func `a second Claude account is named from its address, and replacing puts it in the default`() throws {
        _ = try registry.storeSignIn(.claude(claude("me@example.com", "one")), defaultFile: defaultFile, replace: false)
        #expect(
            try registry.storeSignIn(
                .claude(claude("jane@corp.example", "two")), defaultFile: defaultFile, replace: false)
                == .newConnection("claude-jane"))
        #expect(try defaultFile.loadClaude()?.accessToken == "one")
        #expect(
            try registry.storeSignIn(
                .claude(claude("bob@corp.example", "three")), defaultFile: defaultFile, replace: true)
                == .defaultSignIn)
        #expect(try defaultFile.loadClaude()?.accountEmail == "bob@corp.example")
    }
}
