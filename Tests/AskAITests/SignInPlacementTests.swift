internal import Foundation
internal import Testing

@testable import AskAI

/// Roadmap 0092: a sign-in without a name never replaces another account. The default takes it when it is empty or holds the same
/// account; a connection that already holds the account takes it back; any other account becomes a new connection beside the default.
struct SignInPlacementTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-placement-\(UUID().uuidString)")
    private var registry: ConnectionRegistry { ConnectionRegistry(directory: root.appending(path: "connections")) }
    private var defaultFile: CredentialFile { CredentialFile(url: root.appending(path: "credentials.json")) }

    private func codex(_ account: String) -> CodexCredentials {
        CodexCredentials(accessToken: "t", refreshToken: "r", expiresAt: 9, accountID: account)
    }

    private func claude(_ email: String?) -> ClaudeCredentials {
        ClaudeCredentials(
            accessToken: "a", refreshToken: "r", expiresAt: 9, refreshExpiresAt: nil, accountEmail: email,
            organizationName: nil, scopes: "user:inference")
    }

    private func place(_ identity: AccountIdentity?, _ kind: ConnectionKind, replace: Bool = false) throws
        -> SignInPlacement
    {
        try registry.placement(of: identity, kind: kind, defaultFile: defaultFile, replace: replace)
    }

    @Test func `the first sign-in goes to the default`() throws {
        #expect(try place(.codex("acct_1"), .codex) == .defaultSignIn)
        #expect(try place(.claude("me@example.com"), .anthropic) == .defaultSignIn)
    }

    @Test func `the same account again refreshes the default, whatever the case of its address`() throws {
        try defaultFile.saveCodex(codex("acct_1"))
        try defaultFile.saveClaudeSubscription(claude("Me@Example.com"))
        #expect(try place(.codex("acct_1"), .codex) == .defaultSignIn)
        #expect(try place(.claude("me@example.com"), .anthropic) == .defaultSignIn)
    }

    @Test func `another account becomes a new connection, the default kept`() throws {
        try defaultFile.saveCodex(codex("acct_1"))
        try defaultFile.saveClaudeSubscription(claude("me@example.com"))
        #expect(try place(.codex("acct_2"), .codex) == .newConnection("codex-2"))
        #expect(try place(.claude("Jane.Doe+work@corp.example"), .anthropic) == .newConnection("claude-jane.doe-work"))
    }

    @Test func `a new connection's name skips the names in use`() throws {
        try defaultFile.saveCodex(codex("acct_1"))
        _ = try registry.register(name: "codex-2", provider: .codex)
        _ = try registry.register(name: "codex-3", provider: .codex)
        #expect(try place(.codex("acct_9"), .codex) == .newConnection("codex-4"))
        try defaultFile.saveClaudeSubscription(claude("me@example.com"))
        _ = try registry.register(name: "claude-jane", provider: .anthropic)
        #expect(try place(.claude("jane@corp.example"), .anthropic) == .newConnection("claude-jane-2"))
    }

    @Test func `a connection that holds the account takes it back`() throws {
        try defaultFile.saveCodex(codex("acct_1"))
        let work = try registry.register(name: "work", provider: .codex)
        try registry.saveCodex(codex("acct_2"), for: work)
        #expect(try place(.codex("acct_2"), .codex) == .connection("work"))
    }

    @Test func `replacing puts any account in the default`() throws {
        try defaultFile.saveCodex(codex("acct_1"))
        #expect(try place(.codex("acct_2"), .codex, replace: true) == .defaultSignIn)
    }

    @Test func `an account of unknown identity never replaces a signed-in default`() throws {
        try defaultFile.saveClaudeSubscription(claude(nil))
        #expect(try place(.claude("me@example.com"), .anthropic) == .newConnection("claude-me"))
        try defaultFile.saveClaudeSubscription(claude("me@example.com"))
        #expect(try place(nil, .anthropic) == .newConnection("claude-2"))
    }

    @Test func `the other provider's default does not count`() throws {
        try defaultFile.saveCodex(codex("acct_1"))
        #expect(try place(.claude("me@example.com"), .anthropic) == .defaultSignIn)
    }
}
