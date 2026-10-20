internal import Foundation
internal import Testing

@testable import AskAI

/// Every save is one short transaction: take a lock, read, change one record, rename, let go. Without it two ask processes
/// that read the same file both write it back, and the later one erases the earlier one's sign-in.
///
/// Measured before this (diary 30): eight concurrent saves of different providers kept one or two, in all 20 rounds, with
/// no error thrown. flock is per open file description, so separate descriptors in one process conflict exactly as two
/// processes do (probed with a second process and SIGKILL, diary 30).
@Suite("Credential saves are transactions, so concurrent sign-ins cannot erase each other")
struct CredentialFileTransactionTests {
    private func fresh(lockWait: Duration = .seconds(5)) -> CredentialFile {
        CredentialFile(
            url: FileManager.default.temporaryDirectory.appending(
                path: "ask-txn-\(UUID().uuidString)/ask/credentials.json"),
            lockWait: lockWait)
    }

    private let claude = ClaudeCredentials(
        accessToken: "a", refreshToken: "r", expiresAt: 1, refreshExpiresAt: nil, accountEmail: nil,
        organizationName: nil, scopes: "s")
    private let codex = CodexCredentials(accessToken: "ca", refreshToken: "cr", expiresAt: 1, accountID: "acct")

    @Test(arguments: [false, true])
    func `concurrent saves of every kind of credential all survive`(seeded: Bool) async throws {
        for round in 0 ..< 8 {
            let file = fresh()
            if seeded { try file.saveKey(StoredKey(key: "seed", obtainedAt: 0), for: "seed") }
            let keys = (0 ..< 6).map { "provider-\($0)" }
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try file.saveClaude(claude) }
                group.addTask { try file.saveCodex(codex) }
                for key in keys {
                    group.addTask { try file.saveKey(StoredKey(key: key, obtainedAt: Double(round)), for: key) }
                }
                try await group.waitForAll()
            }
            #expect(try file.loadClaude() == claude, "round \(round): Claude's credentials were lost")
            #expect(try file.loadCodex() == codex, "round \(round): Codex's credentials were lost")
            #expect(try file.loadKeys().keys.filter { $0.hasPrefix("provider-") }.sorted() == keys, "round \(round)")
            if seeded { #expect(try file.loadKey(for: "seed") != nil, "round \(round): the seed was lost") }
        }
    }

    @Test func `a save that cannot get the lock says so and leaves the file alone`() async throws {
        let file = fresh(lockWait: .milliseconds(150))
        try file.saveClaude(claude)
        let before = try Data(contentsOf: file.url)
        let held = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1), name: "write")
        defer { held.release() }
        #expect(throws: CredentialFileError.locked(path: file.url.path + ".write.lock")) {
            try file.saveKey(StoredKey(key: "k", obtainedAt: 1), for: "spettro")
        }
        #expect(try Data(contentsOf: file.url) == before)
    }

    @Test func `the lock is let go after a save, including a save that fails`() async throws {
        let file = fresh(lockWait: .milliseconds(150))
        try file.saveClaude(claude)
        try file.saveKey(StoredKey(key: "k", obtainedAt: 1), for: "spettro")
        try await CredentialLock.acquire(beside: file.url, wait: .milliseconds(200), name: "write").release()
        try Data("{not json".utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.damaged(path: file.url.path)) { try file.saveClaude(claude) }
        try await CredentialLock.acquire(beside: file.url, wait: .milliseconds(200), name: "write").release()
    }

    @Test func `a lock dropped without being released is let go, so a forgotten release cannot wedge every ask`()
        async throws
    {
        let file = fresh()
        try file.saveClaude(claude)
        do { _ = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1), name: "write") }
        try await CredentialLock.acquire(beside: file.url, wait: .milliseconds(300), name: "write").release()
    }

    @Test func `the refresh lock and the save lock are different, so a refresh can save while it holds its own`()
        async throws
    {
        let file = fresh(lockWait: .milliseconds(300))
        try file.saveClaude(claude)  // makes the directory the locks live in
        let refresh = try await CredentialLock.acquire(beside: file.url, wait: .seconds(1))
        defer { refresh.release() }
        try file.saveCodex(codex)
        #expect(try file.loadCodex() == codex)
    }

    @Test func `reading takes no lock and writes nothing, so a read-only look never changes the directory`() throws {
        let file = fresh()
        try file.saveClaude(claude)
        let directory = file.url.deletingLastPathComponent().path
        let before = try FileManager.default.contentsOfDirectory(atPath: directory).sorted()
        let bytes = try Data(contentsOf: file.url)
        _ = try file.loadClaude()
        _ = try file.loadCodex()
        _ = try file.loadKeys()
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory).sorted() == before)
        #expect(try Data(contentsOf: file.url) == bytes)
    }

    @Test func `a replacement made while the stored credentials are still the expected ones is stored whole`() throws {
        let file = fresh()
        try file.saveCodex(codex)
        try file.saveKey(StoredKey(key: "k", obtainedAt: 1), for: "spettro")
        let newer = CodexCredentials(accessToken: "n", refreshToken: "nr", expiresAt: 9, accountID: "acct")
        #expect(try file.saveCodex(newer, ifStill: codex))
        #expect(try file.loadCodex() == newer)
        #expect(try file.loadKey(for: "spettro") == StoredKey(key: "k", obtainedAt: 1), "other providers are kept")
        let claudeNewer = ClaudeCredentials(
            accessToken: "b", refreshToken: "s", expiresAt: 9, refreshExpiresAt: nil, accountEmail: nil,
            organizationName: nil, scopes: "s")
        try file.saveClaude(claude)
        #expect(try file.saveClaude(claudeNewer, ifStill: claude))
        #expect(try file.loadClaude() == claudeNewer)
    }

    @Test func `a replacement is refused, and writes nothing, when the credentials changed or were removed`() throws {
        let file = fresh()
        let other = CodexCredentials(accessToken: "x", refreshToken: "xr", expiresAt: 5, accountID: "other")
        try file.saveCodex(other)
        let before = try Data(contentsOf: file.url)
        #expect(try !file.saveCodex(codex, ifStill: codex))
        #expect(try Data(contentsOf: file.url) == before, "someone else's sign-in is never overwritten")
        try file.removeCodex()
        #expect(try !file.saveCodex(codex, ifStill: codex))
        #expect(try file.loadCodex() == nil, "a removed sign-in is not brought back")
        let none = fresh()
        #expect(try !none.saveClaude(claude, ifStill: claude))
        #expect(
            !FileManager.default.fileExists(atPath: none.url.path), "no credentials file is made for a refused save")
        let directory = none.url.deletingLastPathComponent().path
        #expect(!FileManager.default.fileExists(atPath: directory), "nor a directory or lock file to hold it")
    }

    @Test func `a replacement on a damaged file is an error and leaves the file as it was`() throws {
        let file = fresh()
        try file.saveCodex(codex)
        try Data("{not json".utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.damaged(path: file.url.path)) { try file.saveCodex(codex, ifStill: codex) }
        #expect(String(decoding: try Data(contentsOf: file.url), as: UTF8.self) == "{not json")
    }
}
