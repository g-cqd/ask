import Foundation
import Testing

@testable import AskAI

/// Turning stored credentials into request auth: no network while fresh, refresh-and-save when expiring.
@Suite("Access uses stored credentials and refreshes them only when they expire")
struct ClaudeAccessTests {
    private let file = CredentialFile(
        url: FileManager.default.temporaryDirectory.appending(
            path: "ask-access-\(UUID().uuidString)/ask/credentials.json"))
    private let refreshed =
        #"{"token_type":"bearer","access_token":"sk-ant-oat-NEW","refresh_token":"sk-ant-ort-NEW","#
        + #""expires_in":3600,"scope":"user:inference"}"#

    private func stored(expiresAt: Double) throws {
        try file.saveClaude(
            ClaudeCredentials(
                accessToken: "sk-ant-oat-OLD", refreshToken: "sk-ant-ort-OLD", expiresAt: expiresAt,
                refreshExpiresAt: nil,
                accountEmail: "a@b.c", organizationName: nil, scopes: "user:inference"))
    }

    @Test func `signed out is its own error`() async {
        let access = ClaudeAccess(
            file: file, client: ClaudeAuthClient(transport: ScriptedTransport(status: 500, chunks: [])))
        await #expect(throws: ClaudeAccessError.signedOut) { _ = try await access.auth(now: 0) }
    }

    @Test func `fresh credentials are used without touching the network`() async throws {
        try stored(expiresAt: 1_000)
        let transport = ScriptedTransport(status: 500, chunks: [])
        let auth = try await ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport)).auth(now: 999)
        #expect(auth == .subscription(accessToken: "sk-ant-oat-OLD"))
        #expect(transport.sent == nil)
    }

    @Test func `expiring credentials are refreshed and the new ones saved`() async throws {
        try stored(expiresAt: 1_000)
        let transport = ScriptedTransport(status: 200, chunks: [refreshed])
        let auth = try await ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport)).auth(now: 1_000)
        #expect(auth == .subscription(accessToken: "sk-ant-oat-NEW"))
        let saved = try #require(try file.loadClaude())
        #expect(saved.refreshToken == "sk-ant-ort-NEW")
        #expect(saved.accountEmail == "a@b.c")
    }

    @Test func `a rejected refresh keeps what was stored and says to sign in again`() async throws {
        try stored(expiresAt: 1_000)
        let transport = ScriptedTransport(status: 400, chunks: [#"{"error":"invalid_grant"}"#])
        await #expect(throws: ClaudeAccessError.refreshFailed(.tokenEndpoint(status: 400, code: "invalid_grant"))) {
            _ = try await ClaudeAccess(file: file, client: ClaudeAuthClient(transport: transport)).auth(now: 2_000)
        }
        #expect(try file.loadClaude()?.refreshToken == "sk-ant-ort-OLD")
    }
}
