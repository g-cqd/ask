internal import Foundation
internal import Testing

@testable import AskAI

struct ConnectionBindingTests {
    @Test func `a selected authorization identity cannot follow a replacement account`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-binding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = ConnectionRegistry(directory: root)
        let record = try registry.register(name: "work", provider: .codex)
        let a = CodexCredentials(accessToken: "a", refreshToken: "ar", expiresAt: 1000, accountID: "account-a")
        let b = CodexCredentials(accessToken: "b", refreshToken: "br", expiresAt: 1000, accountID: "account-b")
        try registry.saveCodex(a, for: record)
        let file = registry.credentials(for: record)
        #expect(try file.loadCodex(connection: record) == a)
        try registry.rename(record, to: "employer")
        #expect(try file.loadCodex(connection: record) == a, "a rename does not change the identity")
        try registry.saveCodex(b, for: record, replaceAccount: true)
        #expect(throws: CredentialFileError.connectionChanged(path: file.url.path)) {
            try file.loadCodex(connection: record)
        }
    }

    @Test func `a selected registration cannot follow logout or removal`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-binding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let registry = ConnectionRegistry(directory: root)
        let record = try registry.register(name: "work", provider: .anthropic)
        let credentials = ClaudeCredentials(
            accessToken: "a", refreshToken: "r", expiresAt: 1000, refreshExpiresAt: nil,
            accountEmail: "a@example.test", organizationName: nil, scopes: "s")
        try registry.saveClaude(credentials, for: record)
        let file = registry.credentials(for: record)
        #expect(try file.loadClaude(connection: record) == credentials)
        try registry.signOut(record)
        #expect(throws: CredentialFileError.connectionChanged(path: file.url.path)) {
            try file.loadClaude(connection: record)
        }
    }
}
