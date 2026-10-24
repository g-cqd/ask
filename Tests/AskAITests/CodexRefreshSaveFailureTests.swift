internal import Foundation
internal import Testing

@testable import AskAI

/// The same fault as Claude's (roadmap 0056, ADR-0082) in Codex's twin: a refresh the server accepted whose save fails must not leave
/// the spent single-use token as the only copy a later run can find.
@Suite("A Codex refresh whose save fails keeps the rotated credentials until they can be saved")
struct CodexRefreshSaveFailureTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-codex-save-failure-\(UUID().uuidString)/ask/credentials.json"),
        lockWait: .milliseconds(50))
    private static let spent = #"{"error":"refresh_token_reused"}"#
    private let expired = CodexCredentials(
        accessToken: "old", refreshToken: "rt-1", expiresAt: 100, accountID: "acct_a")

    private func holdingTheSaveLock() throws -> CredentialLock {
        try CredentialLock.acquireBlocking(beside: file.url, wait: .seconds(1), name: "write")
    }

    @Test func `the request that rotated the token goes ahead with the new one, and the next call saves it`()
        async throws
    {
        try file.saveCodex(expired)
        let transport = SequencedTransport([.json(200, CodexAccessTests.tokens), .json(400, Self.spent)])
        let access = CodexAccess(file: file, client: CodexAuthClient(transport: transport))
        let held = try holdingTheSaveLock()
        let first = try await access.credentials(now: 5_000)
        #expect(first.refreshToken == "rt-2" && access.rotationIsUnsaved)
        #expect(try file.loadCodex()?.refreshToken == "rt-1", "the file still holds the spent token")
        held.release()
        let second = try await access.credentials(now: 5_000)
        #expect(second == first)
        #expect(transport.sent.count == 1, "the spent token was never offered again")
        #expect(try file.loadCodex() == first && !access.rotationIsUnsaved)
    }

    private static let third =
        #"{"access_token":"\#(CodexAccessTests.freshAccess)","refresh_token":"rt-3","expires_in":3600}"#

    @Test
    func `while the save keeps failing, the held credentials serve requests and the next refresh starts from them`()
        async throws
    {
        try file.saveCodex(expired)
        let transport = SequencedTransport([.json(200, CodexAccessTests.tokens), .json(200, Self.third)])
        let access = CodexAccess(file: file, client: CodexAuthClient(transport: transport))
        let held = try holdingTheSaveLock()
        defer { held.release() }
        let first = try await access.credentials(now: 5_000)
        #expect(try await access.credentials(now: 5_000) == first, "served from memory, with nothing sent")
        #expect(transport.sent.count == 1)
        let later = try await access.credentials(now: 100_000)
        #expect(later.refreshToken == "rt-3")
        #expect(
            String(decoding: transport.sent[1].body, as: UTF8.self).contains("rt-2"), "refreshed from the rotated token"
        )
    }

    @Test func `a lock that frees up during the second refresh lets that one step bring the file up to date`()
        async throws
    {
        try file.saveCodex(expired)
        let inner = SequencedTransport([.json(200, CodexAccessTests.tokens), .json(200, Self.third)])
        let held = try holdingTheSaveLock()
        let access = CodexAccess(
            file: file, client: CodexAuthClient(transport: ReleaseOnSendTransport(inner, releasing: held, at: 2)))
        _ = try await access.credentials(now: 5_000)
        let later = try await access.credentials(now: 100_000)
        #expect(later.refreshToken == "rt-3")
        #expect(try file.loadCodex() == later && !access.rotationIsUnsaved)
    }

    @Test func `a new sign-in made meanwhile is not overwritten by the held credentials`() async throws {
        try file.saveCodex(expired)
        let transport = SequencedTransport([.json(200, CodexAccessTests.tokens), .json(400, Self.spent)])
        let access = CodexAccess(file: file, client: CodexAuthClient(transport: transport))
        let held = try holdingTheSaveLock()
        _ = try await access.credentials(now: 5_000)
        held.release()
        let login = CodexCredentials(
            accessToken: "login", refreshToken: "rt-9", expiresAt: 1_000_000, accountID: "acct_a")
        try file.saveCodex(login)
        #expect(try await access.credentials(now: 5_000) == login)
        #expect(!access.rotationIsUnsaved)
    }
}
