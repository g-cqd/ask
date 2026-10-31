import Foundation
import Testing

@testable import AskAI

/// A file's secrets are found again whichever way its path is spelled (roadmap 0110): through a symlink, as a `~/.config` kept in a
/// dotfiles folder is, or through `/private/var` for `/var`. Keyed by the path as written, a signed ask stored them under one
/// spelling and looked under the other, found nothing, and dropped the account (probe-model-accounts on a signed build).
@Suite("A credential file's items are named by the file, not by its path's spelling")
struct CredentialAccountNameTests {
    private let store = MemorySecretStore()
    private let claude = ClaudeCredentials(
        accessToken: "sk-ant-oat-SECRET-A", refreshToken: "sk-ant-ort-SECRET-R", expiresAt: 1_000,
        refreshExpiresAt: nil, accountEmail: "a@b.c", organizationName: nil, scopes: "user:inference")

    private func directory() throws -> URL {
        let made = FileManager.default.temporaryDirectory.appending(path: "ask-account-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        return made
    }

    @Test func `saved through a symlinked folder, it loads through the real one, and the other way`() throws {
        let real = try directory()
        let link = try directory().appending(path: "linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try CredentialFile(url: link.appending(path: "credentials.json"), secrets: store).saveClaude(claude)
        #expect(
            try CredentialFile(url: real.appending(path: "credentials.json"), secrets: store).loadClaude() == claude)
        try CredentialFile(url: real.appending(path: "credentials.json"), secrets: store)
            .saveKey(
                StoredKey(key: "sk-SECRET", obtainedAt: 1), for: "mistral")
        #expect(
            try CredentialFile(url: link.appending(path: "credentials.json"), secrets: store).loadKey(for: "mistral")?
                .key
                == "sk-SECRET")
    }

    @Test func `saved under /var, it loads under /private/var`() throws {
        let plain = try directory()
        try #require(plain.path.hasPrefix("/var/"), "the temporary folder is under /var on macOS")
        try CredentialFile(url: plain.appending(path: "credentials.json"), secrets: store).saveClaude(claude)
        let spelled = URL(filePath: "/private" + plain.path).appending(path: "credentials.json")
        #expect(try CredentialFile(url: spelled, secrets: store).loadClaude() == claude)
    }
}
