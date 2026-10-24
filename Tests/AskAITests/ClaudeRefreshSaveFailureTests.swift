internal import Foundation
internal import Testing

@testable import AskAI

/// Found by the TLA+ model `docs/formal/CredentialRefresh.tla`: with `MaySaveFail` on, TLC reaches, in four steps, a state
/// where the server has accepted the stored refresh token and the file still holds it. A refresh that the server accepted
/// but whose save failed (the save lock held past `lockWait`, a full disk, a failed rename) drops the rotated credentials
/// (`ClaudeAccess.auth` throws `.storage`), and the single-use token left in the file is refused from then on (ADR-0073).
/// The user is signed out by a failure that was only transient.
struct ClaudeRefreshSaveFailureTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-claude-save-failure-\(UUID().uuidString)/ask/credentials.json"),
        lockWait: .milliseconds(50))

    private static let refreshed =
        #"{"token_type":"bearer","access_token":"sk-ant-oat-NEW","refresh_token":"sk-ant-ort-NEW","expires_in":3600,"scope":"user:inference"}"#
    private static let spent = #"{"error":"invalid_grant","error_description":"Refresh token not found or invalid"}"#

    private func storeExpired() throws {
        try file.saveClaude(
            ClaudeCredentials(
                accessToken: "sk-ant-oat-OLD", refreshToken: "sk-ant-ort-OLD", expiresAt: 100, refreshExpiresAt: nil,
                accountEmail: "a@b.example", organizationName: nil, scopes: "user:inference"))
    }

    @Test func `a save that fails after the server accepted the refresh does not leave the spent token stored`()
        async throws
    {
        try storeExpired()
        let transport = SequencedTransport([.json(200, Self.refreshed), .json(400, Self.spent)])
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))

        // Another ask holds the save lock for longer than this one waits, so the save cannot complete.
        let held = try CredentialLock.acquireBlocking(beside: file.url, wait: .seconds(1), name: "write")
        await #expect(
            throws: ClaudeAccessError.storage(.locked(path: CredentialLock.path(beside: file.url, name: "write")))
        ) {
            _ = try await access.auth(now: 5_000)
        }
        held.release()

        // The server answered the one request it was sent, so it now holds the old token as spent.
        #expect(transport.sent.count == 1)
        withKnownIssue("the rotated credentials are dropped when their save fails, and the spent token stays stored") {
            let stored = try file.loadClaude()?.refreshToken
            #expect(stored != "sk-ant-ort-OLD", "the stored refresh token is one the server already accepted")
        }
    }

    @Test func `the next ask then offers the spent token and is refused, so the failure signs the user out`()
        async throws
    {
        try storeExpired()
        let transport = SequencedTransport([.json(200, Self.refreshed), .json(400, Self.spent)])
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))
        let held = try CredentialLock.acquireBlocking(beside: file.url, wait: .seconds(1), name: "write")
        _ = try? await access.auth(now: 5_000)
        held.release()

        // A later run, with the lock free again.
        await withKnownIssue("a transient save failure costs the sign-in") {
            _ = try await access.auth(now: 5_000)
        }
        #expect(transport.sent.count == 2, "the second run offered the stored token, which was the spent one")
    }
}
