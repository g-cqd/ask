internal import Foundation
internal import Testing

@testable import AskAI

/// A refresh reads credentials, waits on the network, and saves. The user can sign out, or sign in as someone else, in
/// the middle. What the user did last is what stands: a response from a request begun before it must not undo it.
@Suite("A refresh cannot undo a sign-out or a new sign-in made while it was waiting")
struct CredentialRefreshRaceTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-race-\(UUID().uuidString)/ask/credentials.json"))
    private let expired = CodexCredentials(
        accessToken: "old", refreshToken: "rt-1", expiresAt: 100, accountID: "acct_a")
    private let newLogin = CodexCredentials(
        accessToken: "login", refreshToken: "rt-9", expiresAt: 90_000, accountID: "acct_b")
    private static let tokens = CodexAccessTests.tokens

    /// Starts a refresh, holds its request open, runs `meanwhile`, then lets the response arrive.
    private func refreshing(_ meanwhile: () throws -> Void) async throws -> Result<CodexCredentials, CodexAccessError> {
        try file.saveCodex(expired)
        let transport = GatedTransport(status: 200, text: Self.tokens)
        let access = CodexAccess(file: file, client: CodexAuthClient(transport: transport))
        let refresh = Task { () -> Result<CodexCredentials, CodexAccessError> in
            do throws(CodexAccessError) { return .success(try await access.credentials(now: 5_000)) } catch {
                return .failure(error)
            }
        }
        await transport.waitUntilRequested()
        try meanwhile()
        transport.release()
        return await refresh.value
    }

    @Test func `signing out while a refresh is waiting wins, and the sign-in is not brought back`() async throws {
        let result = try await refreshing { try file.removeCodex() }
        #expect(result == .failure(.signedOut))
        #expect(try file.loadCodex() == nil)
    }

    @Test func `signing in again while a refresh is waiting wins, and the new sign-in is what is used`() async throws {
        let result = try await refreshing { try file.saveCodex(newLogin) }
        #expect(result == .success(newLogin))
        #expect(try file.loadCodex() == newLogin, "the older grant's refreshed pair must not replace the new login")
    }

    @Test func `a refreshed pair that cannot be saved is reported and never used`() async throws {
        let directory = file.url.deletingLastPathComponent().path
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory) }
        let result = try await refreshing {
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory)
        }
        guard case .failure(.storage) = result else {
            Issue.record("expected a storage error, got \(result)")
            return
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory)
        #expect(try file.loadCodex() == expired, "the old credentials are intact when the new ones could not be saved")
    }

    @Test func `the same rule holds for Claude`() async throws {
        let stored = ClaudeCredentials(
            accessToken: "old", refreshToken: "rt", expiresAt: 100, refreshExpiresAt: nil, accountEmail: nil,
            organizationName: nil, scopes: "user:inference")
        try file.saveClaude(stored)
        let reply =
            #"{"token_type":"bearer","access_token":"new","refresh_token":"rt2","expires_in":3600,"scope":"user:inference"}"#
        let transport = GatedTransport(status: 200, text: reply)
        let access = ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport))
        let refresh = Task { try await access.auth(now: 5_000) }
        await transport.waitUntilRequested()
        try file.removeClaude()
        transport.release()
        await #expect(throws: ClaudeAccessError.signedOut) { _ = try await refresh.value }
        #expect(try file.loadClaude() == nil)
    }
}
