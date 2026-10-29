import Foundation
import Synchronization
import Testing

@testable import AskAI

/// Keys and tokens in a secret store, the rest in the file (roadmap 0110): the file keeps only a marker where a secret was, every
/// load puts the secrets back, removing a record removes its item, and a store that fails leaves the file as it was.
@Suite("Secrets live in the secret store, the rest in the file")
struct CredentialSecretsTests {
    private let directory = FileManager.default.temporaryDirectory.appending(
        path: "ask-secrets-\(UUID().uuidString)/ask")
    private let store = MemorySecretStore()
    private let claude = ClaudeCredentials(
        accessToken: "sk-ant-oat-SECRET-A", refreshToken: "sk-ant-ort-SECRET-R", expiresAt: 1_000,
        refreshExpiresAt: nil,
        accountEmail: "a@b.c", organizationName: nil, scopes: "user:inference")

    private var url: URL { directory.appending(path: "credentials.json") }
    private var file: CredentialFile { CredentialFile(url: url, secrets: store) }
    private func bytes() throws -> String { try String(decoding: Data(contentsOf: url), as: UTF8.self) }

    @Test func `a sign-in's tokens go to the store, its metadata stays in the file, and it loads back whole`() throws {
        try file.saveClaude(claude)
        let text = try bytes()
        #expect(!text.contains("SECRET"), "no token in the file")
        #expect(text.contains("a@b.c") && text.contains("1000"), "the metadata stays in the file")
        #expect(store.items.withLock { $0[url.path + "#claude"] }?["refreshToken"] == "sk-ant-ort-SECRET-R")
        #expect(try file.loadClaude() == claude)
    }

    @Test func `an API key goes to the store under its provider`() throws {
        try file.saveKey(StoredKey(key: "sk-SECRET-key", obtainedAt: 5), for: "mistral")
        #expect(!(try bytes()).contains("SECRET"))
        #expect(store.items.withLock { $0[url.path + "#keys.mistral"] }?["key"] == "sk-SECRET-key")
        #expect(try file.loadKey(for: "mistral")?.key == "sk-SECRET-key")
    }

    @Test func `removing a record removes its item, and removing the file removes them all`() throws {
        try file.saveClaude(claude)
        try file.saveKey(StoredKey(key: "sk-SECRET-key", obtainedAt: 5), for: "mistral")
        try file.removeClaude()
        #expect(store.items.withLock { $0[url.path + "#claude"] } == nil)
        #expect(store.items.withLock { $0[url.path + "#keys.mistral"] } != nil)
        try file.remove()
        #expect(store.items.withLock { $0.isEmpty })
    }

    @Test func `secrets already in the file move to the store, and the file keeps none`() throws {
        try CredentialFile(url: url).saveClaude(claude)
        #expect(try bytes().contains("SECRET"))
        try file.settleSecrets()
        #expect(!(try bytes()).contains("SECRET"))
        #expect(try file.loadClaude() == claude)
    }

    @Test func `back in file mode, secrets come back from the store into the file`() throws {
        try file.saveClaude(claude)
        let fileOnly = CredentialFile(url: url, secrets: nil, vault: store)
        try fileOnly.settleSecrets()
        #expect(try bytes().contains("sk-ant-ort-SECRET-R"))
        #expect(store.items.withLock { $0.isEmpty }, "the items are gone once the file holds the secrets")
        #expect(try CredentialFile(url: url).loadClaude() == claude)
    }

    @Test func `a marked record whose item is gone is an error, not a sign-out`() throws {
        try file.saveClaude(claude)
        store.items.withLock { $0.removeAll() }
        #expect(throws: CredentialFileError.secretMissing(path: url.path, record: "claude")) { try file.loadClaude() }
    }

    @Test func `a store that cannot be written leaves the file as it was`() throws {
        try file.saveClaude(claude)
        let before = try bytes()
        store.failWrites.withLock { $0 = true }
        var newer = claude
        newer.accessToken = "sk-ant-oat-SECRET-B"
        #expect(throws: CredentialFileError.self) { try file.saveClaude(newer) }
        #expect(try bytes() == before)
        store.failWrites.withLock { $0 = false }
        #expect(try file.loadClaude() == claude)
    }
}
