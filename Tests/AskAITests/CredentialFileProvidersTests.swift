import Foundation
import Testing

@testable import AskAI

/// One file holds every provider's credentials, and saving one never loses another's.
///
/// Before this, the file held only Claude's and a save rewrote all of it: the first other provider to sign in would
/// have signed the user out of Claude.
@Suite("Each provider's credentials are kept apart in the one credential file")
struct CredentialFileProvidersTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-creds-\(UUID().uuidString)/ask/credentials.json"))
    private let claude = ClaudeCredentials(
        accessToken: "sk-ant-oat-A", refreshToken: "sk-ant-ort-R", expiresAt: 1_000, refreshExpiresAt: nil,
        accountEmail: nil, organizationName: nil, scopes: "user:inference")

    @Test func `saving a provider's key keeps Claude signed in, and the reverse`() throws {
        try file.saveClaude(claude)
        try file.saveKey(StoredKey(key: "spettro-key", obtainedAt: 5), for: "spettro")
        #expect(try file.loadClaude() == claude)
        try file.saveClaude(claude)
        #expect(try file.loadKey(for: "spettro") == StoredKey(key: "spettro-key", obtainedAt: 5))
    }

    @Test func `providers' keys are kept apart and removed one at a time`() throws {
        try file.saveKey(StoredKey(key: "a", obtainedAt: 1), for: "spettro")
        try file.saveKey(StoredKey(key: "b", obtainedAt: 2), for: "mistral-vibe")
        try file.removeKey(for: "spettro")
        #expect(try file.loadKey(for: "spettro") == nil)
        #expect(try file.loadKey(for: "mistral-vibe") == StoredKey(key: "b", obtainedAt: 2))
        try file.removeKey(for: "spettro")
    }

    @Test func `a file from before keys existed reads as Claude's alone`() throws {
        try file.saveClaude(claude)
        #expect(try file.loadKey(for: "spettro") == nil)
        #expect(try file.storedKeyProviders() == [])
    }

    @Test func `a damaged file is refused, never overwritten by a save`() throws {
        try file.saveClaude(claude)
        try Data("{not json".utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.damaged(path: file.url.path)) {
            try file.saveKey(StoredKey(key: "x", obtainedAt: 1), for: "spettro")
        }
        #expect(String(decoding: try Data(contentsOf: file.url), as: UTF8.self) == "{not json")
    }

    @Test func `which providers have a stored key is listed, in name order`() throws {
        try file.saveKey(StoredKey(key: "b", obtainedAt: 2), for: "spettro")
        try file.saveKey(StoredKey(key: "a", obtainedAt: 1), for: "mistral-vibe")
        #expect(try file.storedKeyProviders() == ["mistral-vibe", "spettro"])
    }
}
