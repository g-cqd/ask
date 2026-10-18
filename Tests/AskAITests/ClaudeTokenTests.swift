import Testing

@testable import AskAI

/// The token endpoint: exact request bodies, strict response validation, and expiry with a safety margin.
/// Rules mirror pi-integrations' `postToken` / `validateTokenResponse` / `toCredentials`.
@Suite("Token responses become credentials only when every field is sound")
struct ClaudeTokenTests {
    private let now = 1_000_000.0

    private func response(_ fields: String) -> [UInt8] {
        Array(#"{"token_type":"Bearer","access_token":"sk-ant-oat-A","refresh_token":"sk-ant-ort-R""#.utf8)
            + Array(fields.utf8) + Array("}".utf8)
    }

    @Test func `the exchange and refresh bodies are exact`() {
        let exchange = String(decoding: ClaudeToken.exchangeBody(code: "C", verifier: "V", state: "S"), as: UTF8.self)
        #expect(
            exchange == #"{"grant_type":"authorization_code","code":"C","#
                + #""redirect_uri":"https://platform.claude.com/oauth/code/callback","#
                + #""client_id":"9d1c250a-e61b-44d9-88ed-5944d1962f5e","code_verifier":"V","state":"S"}"#)
        let refresh = String(decoding: ClaudeToken.refreshBody(refreshToken: "R"), as: UTF8.self)
        #expect(
            refresh == #"{"grant_type":"refresh_token","refresh_token":"R","#
                + #""client_id":"9d1c250a-e61b-44d9-88ed-5944d1962f5e"}"#)
    }

    @Test func `a sound response becomes credentials that expire early`() throws {
        let body = response(
            #","expires_in":28800,"scope":"user:inference","refresh_token_expires_in":604800,"#
                + #""account":{"email_address":"a@b.c"},"organization":{"name":"Org"}"#)
        let credentials = try ClaudeToken.credentials(status: 200, body: body, now: now)
        #expect(
            credentials
                == ClaudeCredentials(
                    accessToken: "sk-ant-oat-A", refreshToken: "sk-ant-ort-R",
                    expiresAt: now + 28_800 - 300, refreshExpiresAt: now + 604_800,
                    accountEmail: "a@b.c", organizationName: "Org", scopes: "user:inference"))
        #expect(!credentials.needsRefresh(now: now + 28_800 - 301))
        #expect(credentials.needsRefresh(now: now + 28_800 - 300))
    }

    @Test func `a short lifetime keeps a tenth of it as margin`() throws {
        let credentials = try ClaudeToken.credentials(
            status: 200, body: response(#","expires_in":600,"scope":"s""#), now: now)
        #expect(credentials.expiresAt == now + 540)
    }

    @Test(arguments: [
        #","expires_in":600"#,  // no scope
        #","expires_in":0,"scope":"s""#,
        #","expires_in":-5,"scope":"s""#,
        #","expires_in":"600","scope":"s""#,
        #","expires_in":600,"scope":"s","refresh_token_expires_in":0"#,
        #","expires_in":600,"scope":"s","account":{"email_address":7}"#,
        #","expires_in":600,"scope":"s","organization":[]"#
    ])
    func `an unsound response is refused`(fields: String) {
        #expect(throws: ClaudeAuthError.invalidResponse) {
            _ = try ClaudeToken.credentials(status: 200, body: response(fields), now: now)
        }
    }

    @Test func `unsound tokens and token types are refused`() {
        let bodies = [
            #"{"token_type":"mac","access_token":"A","refresh_token":"R","expires_in":600,"scope":"s"}"#,
            #"{"token_type":"bearer","access_token":"A B","refresh_token":"R","expires_in":600,"scope":"s"}"#,
            #"{"token_type":"bearer","access_token":"","refresh_token":"R","expires_in":600,"scope":"s"}"#,
            #"{"token_type":"bearer","access_token":"A","expires_in":600,"scope":"s"}"#,
            "not json"
        ]
        for body in bodies {
            #expect(throws: ClaudeAuthError.invalidResponse, "\(body)") {
                _ = try ClaudeToken.credentials(status: 200, body: Array(body.utf8), now: now)
            }
        }
        #expect(throws: Never.self) {
            _ = try ClaudeToken.credentials(
                status: 200,
                body: Array(
                    #"{"token_type":"bearer","access_token":"A","refresh_token":"R","expires_in":1,"scope":""}"#.utf8),
                now: now)
        }
    }

    @Test func `an endpoint error names a known OAuth code and never echoes the body`() {
        #expect(throws: ClaudeAuthError.tokenEndpoint(status: 400, code: "invalid_grant")) {
            _ = try ClaudeToken.credentials(status: 400, body: Array(#"{"error":"invalid_grant"}"#.utf8), now: now)
        }
        #expect(throws: ClaudeAuthError.tokenEndpoint(status: 400, code: nil)) {
            _ = try ClaudeToken.credentials(status: 400, body: Array(#"{"error":"secret token abc"}"#.utf8), now: now)
        }
        #expect(throws: ClaudeAuthError.tokenEndpoint(status: 503, code: nil)) {
            _ = try ClaudeToken.credentials(status: 503, body: Array("<html>".utf8), now: now)
        }
    }
}
