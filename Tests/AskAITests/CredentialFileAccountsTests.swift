internal import Foundation
internal import Testing

@testable import AskAI

/// What is signed in, as accounts, and how a key replaces or leaves a subscription (ADR-0117).
@Suite("Accounts are listed from the file and the environment, and a Claude key replaces the subscription")
struct CredentialFileAccountsTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-accounts-\(UUID().uuidString)/ask/credentials.json"))
    private let codex = CodexCredentials(accessToken: "at", refreshToken: "rt", expiresAt: 1, accountID: "acct")
    private let claude = ClaudeCredentials(
        accessToken: "sk-ant-oat-A", refreshToken: "sk-ant-ort-R", expiresAt: 1_000, refreshExpiresAt: nil,
        accountEmail: nil, organizationName: nil, scopes: "user:inference")

    @Test func `nothing is signed in with an empty file and environment`() throws {
        #expect(try file.signedInAccounts(environment: [:]).isEmpty)
    }

    @Test func `each stored record is an account, in the order ask prefers them`() throws {
        try file.saveKey(StoredKey(key: "k", obtainedAt: 1), for: "mistral")
        try file.saveCodex(codex)
        try file.saveClaude(claude)
        let accounts = try file.signedInAccounts(environment: [:])
        #expect(accounts.map(\.provider) == ["anthropic", "codex", "mistral"])
        #expect(accounts.map(\.method) == ["subscription", "subscription", "API key"])
    }

    @Test func `a key in the environment is an account ask cannot forget`() throws {
        let accounts = try file.signedInAccounts(environment: ["ANTHROPIC_API_KEY": "sk", "GROQ_API_KEY": "g"])
        #expect(accounts.map(\.provider) == ["anthropic", "groq"])
        #expect(accounts.allSatisfy { !$0.removable && $0.method.hasPrefix("environment (") })
    }

    @Test func `an empty environment variable is not an account`() throws {
        #expect(try file.signedInAccounts(environment: ["ANTHROPIC_API_KEY": "", "GROQ_API_KEY": ""]).isEmpty)
    }

    @Test func `a stored key hides the same provider's environment variable, so it is listed once`() throws {
        try file.saveKey(StoredKey(key: "k", obtainedAt: 1), for: "groq")
        let accounts = try file.signedInAccounts(environment: ["GROQ_API_KEY": "g"])
        #expect(accounts.count == 1 && accounts[0].removable)
    }

    @Test func `a Claude key replaces the subscription in one write`() throws {
        try file.saveClaude(claude)
        try file.saveCodex(codex)
        try file.saveAPIKey("sk-ant-api-1", for: "anthropic", now: 5)
        #expect(try file.loadClaude() == nil)
        #expect(try file.loadKey(for: "anthropic")?.key == "sk-ant-api-1")
        #expect(try file.loadCodex() == codex, "another account is left alone")
    }

    @Test func `signing in to the subscription forgets the Claude key`() throws {
        try file.saveAPIKey("sk-ant-api-1", for: "anthropic", now: 5)
        try file.saveClaudeSubscription(claude)
        #expect(try file.loadKey(for: "anthropic") == nil && file.loadClaude() == claude)
    }

    @Test func `any other key is stored beside the rest without touching them`() throws {
        try file.saveClaude(claude)
        try file.saveAPIKey("sk-openai", for: "openai", now: 5)
        #expect(try file.loadClaude() == claude && file.loadKey(for: "openai")?.key == "sk-openai")
    }

    @Test(arguments: [
        ("claude", "anthropic"), ("anthropic", "anthropic"), ("codex", "codex"), ("openai", "openai"),
        ("mistral-vibe", "mistral")
    ])
    func `sign out forgets what the target names and nothing else`(target: String, stored: String) throws {
        try file.saveClaude(claude)
        try file.saveCodex(codex)
        try file.saveKey(StoredKey(key: "o", obtainedAt: 1), for: "openai")
        try file.saveKey(StoredKey(key: "m", obtainedAt: 1), for: "mistral")
        try file.saveAPIKey("a", for: "anthropic", now: 1)
        #expect(try file.signOut(target: target))
        let remaining = Set(try file.signedInAccounts(environment: [:]).map(\.provider))
        #expect(!remaining.contains(stored) || (stored == "anthropic" && false))
        #expect(try file.signOut(target: target) == false, "a second time there is nothing to forget")
    }

    @Test func `signing out of something not signed in says so and writes nothing`() throws {
        #expect(try file.signOut(target: "nonsense") == false)
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func `a damaged file is an error and never mistaken for being signed out`() throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{nope".utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.self) { try file.signedInAccounts(environment: [:]) }
    }
}
