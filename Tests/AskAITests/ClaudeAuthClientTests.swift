import Foundation
import Testing

@testable import AskAI

/// Sign-in and refresh over the transport.
@Suite("Sign-in exchanges a genuine code and refresh replaces expiring credentials")
struct ClaudeAuthClientTests {
    private let sound =
        #"{"token_type":"bearer","access_token":"sk-ant-oat-N","refresh_token":"sk-ant-ort-N","#
        + #""expires_in":3600,"scope":"user:inference"}"#

    @Test func `a genuine pasted code is exchanged with the verifier and state`() async throws {
        let transport = ScriptedTransport(status: 200, chunks: [sound])
        let pending = PendingSignIn(pkce: PKCE(verifier: "verifier-value"), state: "0123abcd")
        let credentials = try await ClaudeAuthClient(transport: transport)
            .complete(pending, pasted: "AbCdEfGhIjKlMnOpQrStUv#0123abcd", now: 0)
        #expect(credentials.accessToken == "sk-ant-oat-N")
        let sent = try #require(transport.sent)
        #expect(sent.url.absoluteString == ClaudeOAuth.tokenEndpoint)
        #expect(sent.headers.first { $0.name == "content-type" }?.value == "application/json")
        #expect(
            sent.body
                == ClaudeToken.exchangeBody(
                    code: "AbCdEfGhIjKlMnOpQrStUv", verifier: "verifier-value", state: "0123abcd"))
    }

    @Test func `a code from another sign-in never reaches the network`() async {
        let transport = ScriptedTransport(status: 200, chunks: [sound])
        let pending = PendingSignIn(pkce: PKCE(verifier: "v"), state: "0123abcd")
        await #expect(throws: ClaudeAuthError.invalidPastedCode) {
            _ = try await ClaudeAuthClient(transport: transport)
                .complete(pending, pasted: "AbCdEfGhIjKlMnOpQrStUv#other", now: 0)
        }
        #expect(transport.sent == nil)
    }

    @Test func `refresh sends the refresh token and returns new credentials`() async throws {
        let transport = ScriptedTransport(status: 200, chunks: [sound])
        let old = ClaudeCredentials(
            accessToken: "old", refreshToken: "sk-ant-ort-O", expiresAt: 0, refreshExpiresAt: nil,
            accountEmail: "a@b.c",
            organizationName: nil, scopes: "s")
        let refreshed = try await ClaudeAuthClient(transport: transport).refresh(old, now: 100)
        #expect(refreshed.accessToken == "sk-ant-oat-N")
        #expect(refreshed.expiresAt == 100 + 3_600 - 300)
        #expect(refreshed.accountEmail == "a@b.c", "a refresh that omits the account keeps the known one")
        #expect(transport.sent?.body == ClaudeToken.refreshBody(refreshToken: "sk-ant-ort-O"))
    }

    @Test func `a refused refresh reports the endpoint's code`() async {
        let transport = ScriptedTransport(status: 400, chunks: [#"{"error":"invalid_grant"}"#])
        let old = ClaudeCredentials(
            accessToken: "a", refreshToken: "r", expiresAt: 0, refreshExpiresAt: nil, accountEmail: nil,
            organizationName: nil, scopes: "s")
        await #expect(throws: ClaudeAuthError.tokenEndpoint(status: 400, code: "invalid_grant")) {
            _ = try await ClaudeAuthClient(transport: transport).refresh(old, now: 0)
        }
    }
}
