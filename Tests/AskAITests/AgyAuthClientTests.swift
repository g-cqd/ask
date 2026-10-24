internal import Foundation
internal import Testing

@testable import AskAI

/// Completing a sign-in and refreshing it against Google's token endpoint, with the secret already confirmed (ADR-0072).
struct AgyAuthClientTests {
    private static let secret = "GOCSPX-" + String(repeating: "s", count: 28)
    private static let code = "4/0AeaYSHDqabcdefghij"

    private static func idToken(_ claims: String) -> String {
        func part(_ text: String) -> String { Base64URL.encode(Array(text.utf8)) }
        return part(#"{"alg":"none"}"#) + "." + part(claims) + ".sig"
    }

    private static func tokens(
        access: String = "ya29.access-1", refresh: String? = "1//refresh-1", expires: Double = 3599,
        extra: String =
            #","id_token":"\#(idToken(#"{"email":"person@example.com"}"#))","scope":"openid https://www.googleapis.com/auth/cloud-platform""#
    ) -> String {
        #"{"access_token":"\#(access)","expires_in":\#(Int(expires)),"token_type":"Bearer""#
            + (refresh.map { #","refresh_token":"\#($0)""# } ?? "") + extra + "}"
    }

    private let pending = AgyPendingSignIn(
        pkce: PKCE(verifier: "verifier-value-0123456789"), state: "state-value-abcdefghijkl")

    private func client(_ replies: [SequencedTransport.Reply]) -> (AgyAuthClient, SequencedTransport) {
        let transport = SequencedTransport(replies)
        return (AgyAuthClient(transport: transport), transport)
    }

    @Test func `a pasted code is exchanged with the verifier, the secret and the redirect, and becomes credentials`()
        async throws
    {
        let (client, transport) = client([.json(200, Self.tokens())])
        let credentials = try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 1_000)
        let request = try #require(transport.sent.first)
        #expect(request.url.absoluteString == "https://oauth2.googleapis.com/token" && request.method == "POST")
        #expect(
            request.headers.contains {
                $0.name.lowercased() == "content-type" && $0.value == "application/x-www-form-urlencoded"
            })
        #expect(
            request.bodyText
                == "grant_type=authorization_code&client_id=\(AgyOAuth.clientID)&client_secret=\(Self.secret)"
                + "&code=4%2F0AeaYSHDqabcdefghij&code_verifier=verifier-value-0123456789"
                + "&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback")
        #expect(credentials.accessToken == "ya29.access-1" && credentials.refreshToken == "1//refresh-1")
        #expect(credentials.expiresAt == 1_000 + 3599 - 300, "renewed 300 s early, as the other sign-ins are")
        #expect(credentials.accountEmail == "person@example.com")
        #expect(credentials.scopes == "openid https://www.googleapis.com/auth/cloud-platform")
        #expect(credentials.clientSecret == Self.secret, "kept so a refresh need not find it again")
    }

    @Test func `a paste that is not this sign-in's refuses before any request`() async {
        let (client, transport) = client([.json(200, Self.tokens())])
        await #expect(throws: AgyAuthError.invalidPastedCode) {
            try await client.complete(
                pending, pasted: "code=4/0AeaYSHDqabcdefg&state=wrong", secret: Self.secret, now: 0)
        }
        #expect(transport.sent.isEmpty)
    }

    @Test func `a sign-in that returns no refresh token cannot be renewed, so it is refused`() async {
        let (client, _) = client([.json(200, Self.tokens(refresh: nil))])
        await #expect(throws: AgyAuthError.noRefreshToken) {
            try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0)
        }
    }

    @Test func `a refresh keeps the refresh token when none comes back, and everything else the sign-in learned`()
        async throws
    {
        let old = AgyCredentials(
            accessToken: "ya29.old", refreshToken: "1//keep", expiresAt: 5, scopes: "openid",
            accountEmail: "a@b.example",
            projectID: "project-1", tierID: "free-tier")
        let (client, transport) = client([.json(200, Self.tokens(access: "ya29.new", refresh: nil, extra: ""))])
        let renewed = try await client.refresh(old, secret: Self.secret, now: 2_000)
        #expect(
            try #require(transport.sent.first).bodyText
                == "grant_type=refresh_token&client_id=\(AgyOAuth.clientID)&client_secret=\(Self.secret)&refresh_token=1%2F%2Fkeep"
        )
        #expect(renewed.accessToken == "ya29.new" && renewed.refreshToken == "1//keep")
        #expect(renewed.expiresAt == 2_000 + 3599 - 300)
        #expect(
            renewed.accountEmail == "a@b.example" && renewed.projectID == "project-1" && renewed.tierID == "free-tier")
        #expect(renewed.scopes == "openid")
        #expect(renewed.clientSecret == Self.secret, "the secret that worked is the one kept")
    }

    @Test func `a refresh that returns a new refresh token replaces the old one`() async throws {
        let old = AgyCredentials(accessToken: "a", refreshToken: "1//old", expiresAt: 5)
        let (client, _) = client([.json(200, Self.tokens(refresh: "1//rotated", extra: ""))])
        #expect(try await client.refresh(old, secret: Self.secret, now: 0).refreshToken == "1//rotated")
    }

    @Test(arguments: [
        (400, "invalid_grant"), (401, "invalid_client"), (400, "invalid_request"), (400, "unsupported_grant_type"),
        (403, "access_denied"), (503, "temporarily_unavailable")
    ])
    func `a refusal names the status and a known code and nothing else`(_ status: Int, _ code: String) async {
        let body = #"{"error":"\#(code)","error_description":"secret-looking detail ya29.leak GOCSPX-leak"}"#
        let (client, _) = client([.json(status, body)])
        await #expect(throws: AgyAuthError.tokenEndpoint(status: status, code: code)) {
            try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0)
        }
    }

    @Test func `an unknown error code or a body that is not JSON is a status only`() async {
        for body in [#"{"error":"weird_new_code"}"#, "<html>boom</html>", ""] {
            let (client, _) = client([.json(500, body)])
            await #expect(throws: AgyAuthError.tokenEndpoint(status: 500, code: nil)) {
                try await client.refresh(
                    AgyCredentials(accessToken: "a", refreshToken: "r", expiresAt: 0), secret: Self.secret, now: 0)
            }
        }
    }

    @Test(arguments: [
        #"{}"#, #"{"access_token":"","expires_in":3600,"token_type":"Bearer","refresh_token":"r"}"#,
        #"{"access_token":"has space","expires_in":3600,"token_type":"Bearer","refresh_token":"r"}"#,
        #"{"access_token":"a","expires_in":0,"token_type":"Bearer","refresh_token":"r"}"#,
        #"{"access_token":"a","expires_in":-5,"token_type":"Bearer","refresh_token":"r"}"#,
        #"{"access_token":"a","expires_in":"3600","token_type":"Bearer","refresh_token":"r"}"#,
        #"{"access_token":"a","expires_in":3600,"token_type":"mac","refresh_token":"r"}"#,
        #"{"access_token":"a","expires_in":3600,"refresh_token":"r"}"#,
        #"{"access_token":"a","expires_in":3600,"token_type":"Bearer","refresh_token":"has space"}"#,
        "[]", "null", "not json"
    ])
    func `a success body that is not a sound token response is refused`(_ body: String) async {
        let (client, _) = client([.json(200, body)])
        await #expect(throws: AgyAuthError.invalidResponse) {
            try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0)
        }
    }

    @Test func `an oversized token is refused rather than stored`() async {
        let (client, _) = client([.json(200, Self.tokens(access: String(repeating: "a", count: 16_385)))])
        await #expect(throws: AgyAuthError.invalidResponse) {
            try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0)
        }
    }

    @Test(arguments: [
        #"{"email":"person@example.com"}"#, #"{"email":"first.last+tag@sub.example.co"}"#
    ])
    func `an email in the ID token is shown`(_ claims: String) async throws {
        let (client, _) = client([.json(200, Self.tokens(extra: #","id_token":"\#(Self.idToken(claims))""#))])
        let credentials = try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0)
        #expect(credentials.accountEmail != nil)
    }

    @Test(arguments: [
        #"{"email":"not an email"}"#, #"{"email":"<script>@x.example"}"#, #"{"email":"a@b"}"#, #"{"email":5}"#,
        #"{"name":"x"}"#,
        #"{"email":"\#(String(repeating: "a", count: 300))@example.com"}"#
    ])
    func `an email that is not an ordinary address is not displayed, and never stops the sign-in`(_ claims: String)
        async throws
    {
        let (client, _) = client([.json(200, Self.tokens(extra: #","id_token":"\#(Self.idToken(claims))""#))])
        let credentials = try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0)
        #expect(credentials.accountEmail == nil)
    }

    @Test func `an ID token with the wrong number of parts is not read, even with a good payload`() async throws {
        let payload = Self.idToken(#"{"email":"person@example.com"}"#)
        for token in [payload + ".extra", String(payload.dropLast(4)), ".payload"] {
            let (client, _) = client([.json(200, Self.tokens(extra: #","id_token":"\#(token)""#))])
            #expect(
                try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0).accountEmail == nil)
        }
    }

    @Test func `a damaged ID token is ignored, not an error`() async throws {
        for token in ["", "one-part", "a.b", "a.!!!.c", Self.idToken("not json")] {
            let (client, _) = client([.json(200, Self.tokens(extra: #","id_token":"\#(token)""#))])
            #expect(
                try await client.complete(pending, pasted: Self.code, secret: Self.secret, now: 0).accountEmail == nil)
        }
    }

    @Test func `no description of any failure carries a token or the secret`() {
        let all: [AgyAuthError] = [
            .invalidPastedCode, .noRefreshToken, .invalidResponse, .tokenEndpoint(status: 400, code: "invalid_grant"),
            .tokenEndpoint(status: 500, code: nil)
        ]
        #expect(
            all.allSatisfy {
                !$0.description.contains("GOCSPX") && !$0.description.contains("ya29") && !$0.description.isEmpty
            })
        #expect(AgyAuthError.tokenEndpoint(status: 400, code: "invalid_grant").description.contains("ask login agy"))
    }
}
