internal import Foundation
internal import Testing

@testable import AskAI

/// The token endpoint: an authorization code becomes credentials, and a refresh token is traded for a whole new pair.
///
/// Refresh tokens rotate and are single use, so a refresh returns the replacement in full and an uncertain failure is
/// reported, never retried: a retry would spend a token the server may already have spent.
@Suite("Codex credentials are exchanged and refreshed, and a failure never repeats a secret")
struct CodexAuthClientTests {
    private static let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_9"}}"#
    private static var access: String {
        [Base64URL.encode(Array(#"{"alg":"none"}"#.utf8)), Base64URL.encode(Array(claims.utf8)), "sig"]
            .joined(separator: ".")
    }
    private static var tokens: String {
        #"{"access_token":"\#(access)","refresh_token":"rt-new","expires_in":3600,"id_token":"ignored"}"#
    }

    private func client(_ replies: [SequencedTransport.Reply]) -> (CodexAuthClient, SequencedTransport) {
        let transport = SequencedTransport(replies)
        return (CodexAuthClient(transport: transport), transport)
    }

    private func fields(_ request: HTTPRequest?) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: (request?.bodyText ?? "").split(separator: "&")
                .map { pair in
                    let halves = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    return (halves[0], (halves.count > 1 ? halves[1] : "").removingPercentEncoding ?? "")
                })
    }

    @Test func `an authorization code is exchanged as a form, with the verifier and the redirect it was issued for`()
        async throws
    {
        let (client, transport) = client([.json(200, Self.tokens)])
        let credentials = try await client.exchange(
            code: "the-code", verifier: "the-verifier", redirectURI: "http://localhost:1455/auth/callback", now: 1000)
        let request = transport.sent.first
        #expect(request?.url.absoluteString == "https://auth.openai.com/oauth/token")
        #expect(request?.method == "POST")
        #expect(
            request?.headers.contains { $0.name == "content-type" && $0.value == "application/x-www-form-urlencoded" }
                == true)
        #expect(
            fields(request) == [
                "grant_type": "authorization_code", "client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "code": "the-code",
                "code_verifier": "the-verifier", "redirect_uri": "http://localhost:1455/auth/callback"
            ])
        #expect(credentials.accessToken == Self.access)
        #expect(credentials.refreshToken == "rt-new")
        #expect(credentials.accountID == "acct_9")
    }

    @Test func `the expiry reserves the smaller of five minutes or a tenth of the lifetime`() async throws {
        let long = try await client([.json(200, Self.tokens)]).0
            .exchange(code: "c", verifier: "v", redirectURI: "r", now: 1000)
        #expect(long.expiresAt == 1000 + 3600 - 300)
        let short = #"{"access_token":"\#(Self.access)","refresh_token":"r","expires_in":100}"#
        let brief = try await client([.json(200, short)]).0
            .exchange(code: "c", verifier: "v", redirectURI: "r", now: 1000)
        #expect(brief.expiresAt == 1000 + 100 - 10)
    }

    @Test func `a refresh sends the refresh token and returns the whole replacement pair`() async throws {
        let old = CodexCredentials(accessToken: "old", refreshToken: "rt-old", expiresAt: 5, accountID: "acct_9")
        let (client, transport) = client([.json(200, Self.tokens)])
        let fresh = try await client.refresh(old, now: 2000)
        #expect(
            fields(transport.sent.first) == [
                "grant_type": "refresh_token", "refresh_token": "rt-old", "client_id": "app_EMoamEEZ73f0CkXaXp7hrann"
            ])
        #expect(fresh.refreshToken == "rt-new", "the old refresh token is spent; the new one must replace it")
        #expect(fresh.accessToken == Self.access)
        #expect(fresh.expiresAt == 2000 + 3600 - 300)
    }

    @Test(arguments: [
        (400, #"{"error":"invalid_grant"}"#, "invalid_grant"),
        (400, #"{"error":{"code":"refresh_token_reused"}}"#, "refresh_token_reused"),
        (401, #"{"error":"refresh_token_expired"}"#, "refresh_token_expired"),
        (400, #"{"error":"made_up_code_with_secret_rt-old"}"#, nil as String?), (500, "boom rt-old", nil as String?)
    ])
    func `a refusal names its status and a known code, never the body`(status: Int, body: String, code: String?) async {
        let old = CodexCredentials(accessToken: "old", refreshToken: "rt-old", expiresAt: 5, accountID: "a")
        do {
            _ = try await client([.json(status, body)]).0.refresh(old, now: 1)
            Issue.record("a refusal succeeded")
        } catch {
            #expect(error == .tokenEndpoint(status: status, code: code))
            #expect(!"\(error)".contains("rt-old"))
        }
    }

    @Test(arguments: [
        #"{"refresh_token":"r","expires_in":60}"#, #"{"access_token":"a b","refresh_token":"r","expires_in":60}"#,
        #"{"access_token":"x","refresh_token":"","expires_in":60}"#,
        #"{"access_token":"x","refresh_token":"r","expires_in":0}"#,
        #"{"access_token":"x","refresh_token":"r","expires_in":-5}"#, "not json", "[]"
    ])
    func `a success that is not sound credentials is refused`(body: String) async {
        do {
            _ = try await client([.json(200, body)]).0.exchange(code: "c", verifier: "v", redirectURI: "r", now: 1)
            Issue.record("unsound credentials were accepted")
        } catch { #expect(error == .invalidResponse || error == .noAccountID, "\(error)") }
    }

    @Test func `an access token with no account id is refused, because inference cannot be addressed without one`()
        async
    {
        let body =
            #"{"access_token":"\#(["e30", "e30", "s"].joined(separator: "."))","refresh_token":"r","expires_in":60}"#
        do {
            _ = try await client([.json(200, body)]).0.exchange(code: "c", verifier: "v", redirectURI: "r", now: 1)
            Issue.record("accepted")
        } catch { #expect(error == .noAccountID) }
    }

    @Test func `a transport failure is reported, and the request is not repeated`() async {
        let (client, transport) = client([.failure(HTTPTransportError.failed("offline")), .json(200, Self.tokens)])
        let old = CodexCredentials(accessToken: "o", refreshToken: "rt-old", expiresAt: 5, accountID: "a")
        do {
            _ = try await client.refresh(old, now: 1)
            Issue.record("succeeded")
        } catch { #expect("\(error)".contains("offline")) }
        #expect(transport.sent.count == 1, "a refresh token may already be spent; never retry")
    }
}
