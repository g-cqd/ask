internal import AemiJSON
internal import Foundation
internal import Testing

@testable import AskAI

/// Antigravity's sign-in is stored like every other provider's: whole, under the shared lock, owner-only, beside the others, and
/// compare-and-replace on a refresh (ADR-0039). The verified client secret is kept with it so a refresh never rescans the binary.
struct CredentialFileAgyTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-agy-cred-\(UUID().uuidString)/ask/credentials.json"))

    private let agy = AgyCredentials(
        accessToken: "ya29.access", refreshToken: "1//refresh", expiresAt: 5_000, scopes: "openid",
        accountEmail: "a@b.example",
        projectID: "project-1", tierID: "tier-1", clientSecret: "GOCSPX-" + String(repeating: "s", count: 28))
    private let claude = ClaudeCredentials(
        accessToken: "c", refreshToken: "r", expiresAt: 9, refreshExpiresAt: nil, accountEmail: nil,
        organizationName: nil,
        scopes: "user:inference")
    private let codex = CodexCredentials(accessToken: "x", refreshToken: "y", expiresAt: 9, accountID: "acct")

    @Test func `nothing stored is nil and creates nothing`() throws {
        let stored = try file.loadAgy()
        #expect(stored == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
    }

    @Test func `credentials, including the client secret, are stored whole and read back`() throws {
        try file.saveAgy(agy)
        let loaded = try file.loadAgy()
        #expect(loaded == agy)
        #expect(loaded?.clientSecret == agy.clientSecret)
        let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func `saving Antigravity's credentials keeps every other provider's, and the reverse`() throws {
        try file.saveClaude(claude)
        try file.saveCodex(codex)
        try file.saveKey(StoredKey(key: "k", obtainedAt: 1), for: "groq")
        try file.saveAgy(agy)
        #expect(try file.loadClaude() == claude && file.loadCodex() == codex && file.loadAgy() == agy)
        #expect(try file.loadKey(for: "groq")?.key == "k")
        var newer = claude
        newer.accessToken = "newer"
        try file.saveClaude(newer)
        try file.saveCodex(codex)
        #expect(try file.loadAgy() == agy, "another provider's save must not erase this one")
    }

    @Test func `a record this build does not know is kept verbatim, large numbers and all`() throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let future = #"{"futureProvider":{"id":12345678901234567890,"ratio":0.1000000000000000055511151231257827}}"#
        try Data(future.utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        try file.saveAgy(agy)
        let text = String(decoding: try Data(contentsOf: file.url), as: UTF8.self)
        #expect(text.contains("12345678901234567890") && text.contains("0.1000000000000000055511151231257827"))
        #expect(try file.loadAgy() == agy)
    }

    @Test func `removing Antigravity's credentials keeps the others, and removing nothing is not an error`() throws {
        try file.removeAgy()
        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        try file.saveClaude(claude)
        try file.saveAgy(agy)
        try file.removeAgy()
        #expect(try file.loadAgy() == nil && file.loadClaude() == claude)
        try file.removeAgy()
    }

    @Test func `a record written by an older build, with no client secret, reads with none`() throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try Data(#"{"agy":{"accessToken":"a","refreshToken":"r","expiresAt":7}}"#.utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        let loaded = try file.loadAgy()
        #expect(loaded == AgyCredentials(accessToken: "a", refreshToken: "r", expiresAt: 7))
        #expect(loaded?.clientSecret == nil)
    }

    @Test func `a refresh is saved only while what is stored is still what was refreshed`() throws {
        try file.saveAgy(agy)
        var renewed = agy
        renewed.accessToken = "ya29.renewed"
        #expect(try file.saveAgy(renewed, ifStill: agy))
        #expect(try file.loadAgy() == renewed)
        var stale = agy
        stale.accessToken = "ya29.stale"
        #expect(try !file.saveAgy(stale, ifStill: agy), "the stored credentials changed meanwhile")
        #expect(try file.loadAgy() == renewed)
        try file.removeAgy()
        #expect(try !file.saveAgy(renewed, ifStill: renewed), "signed out meanwhile: nothing is brought back")
        #expect(try file.loadAgy() == nil)
    }

    @Test func `a damaged file is reported and never overwritten`() throws {
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let bytes = Data("{broken".utf8)
        try bytes.write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.damaged(path: file.url.path)) { try file.loadAgy() }
        #expect(throws: CredentialFileError.damaged(path: file.url.path)) { try file.saveAgy(agy) }
        #expect(try Data(contentsOf: file.url) == bytes)
    }

    @Test func `a file other users can read is refused, as for every provider`() throws {
        try file.saveAgy(agy)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.self) { try file.loadAgy() }
    }

    @Test func `forgetting everything forgets Antigravity too`() throws {
        try file.saveAgy(agy)
        try file.remove()
        #expect(try file.loadAgy() == nil)
    }

    @Test func `eight signs-in saved at once keep every provider's record`() async throws {
        try file.saveClaude(claude)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try file.saveAgy(agy) }
            group.addTask { try file.saveCodex(codex) }
            for index in 0 ..< 6 {
                group.addTask { try file.saveKey(StoredKey(key: "k\(index)", obtainedAt: 1), for: "p\(index)") }
            }
            try await group.waitForAll()
        }
        #expect(try file.loadAgy() == agy && file.loadCodex() == codex && file.loadClaude() == claude)
        #expect(try file.loadKeys().count == 6)
    }
}
