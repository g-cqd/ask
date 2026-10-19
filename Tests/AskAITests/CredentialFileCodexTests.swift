internal import Foundation
internal import Testing

@testable import AskAI

/// Codex's credentials live in the credential file beside Claude's and the stored keys, each saved without
/// disturbing the others.
@Suite("Codex credentials are stored whole beside every other provider's")
struct CredentialFileCodexTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-codex-\(UUID().uuidString)/ask/credentials.json"))
    private let codex = CodexCredentials(accessToken: "at", refreshToken: "rt", expiresAt: 1234.5, accountID: "acct_1")
    private let claude = ClaudeCredentials(
        accessToken: "sk-ant-oat-A", refreshToken: "sk-ant-ort-R", expiresAt: 1_000, refreshExpiresAt: nil,
        accountEmail: nil, organizationName: nil, scopes: "user:inference")

    @Test func `saved credentials load back whole`() throws {
        try file.saveCodex(codex)
        #expect(try file.loadCodex() == codex)
    }

    @Test func `nothing stored loads as nothing`() throws { #expect(try file.loadCodex() == nil) }

    @Test func `saving Codex's keeps Claude's and every stored key, and the reverse`() throws {
        try file.saveClaude(claude)
        try file.saveKey(StoredKey(key: "k", obtainedAt: 1), for: "spettro")
        try file.saveCodex(codex)
        #expect(try file.loadClaude() == claude)
        #expect(try file.loadKey(for: "spettro") == StoredKey(key: "k", obtainedAt: 1))
        try file.saveClaude(claude)
        #expect(try file.loadCodex() == codex)
    }

    @Test func `a refresh replaces the whole pair, never one token`() throws {
        try file.saveCodex(codex)
        let fresh = CodexCredentials(accessToken: "at2", refreshToken: "rt2", expiresAt: 9999, accountID: "acct_1")
        try file.saveCodex(fresh)
        #expect(try file.loadCodex() == fresh)
    }

    @Test func `signing out of Codex keeps the rest`() throws {
        try file.saveCodex(codex)
        try file.saveClaude(claude)
        try file.removeCodex()
        #expect(try file.loadCodex() == nil)
        #expect(try file.loadClaude() == claude)
        try file.removeCodex()
    }
}
