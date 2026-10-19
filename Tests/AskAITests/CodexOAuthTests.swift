internal import Foundation
internal import Testing

@testable import AskAI

/// Codex's sign-in constants and the reading of what a browser or a user hands back. Constants and rules are those of
/// pi-integrations' working Codex sign-in; each pasted form must carry the state of this sign-in, with no bare-code
/// shortcut, because a pasted address is the one input an attacker's page can influence.
@Suite("Codex's authorize URL, pasted redirects and account id are built and read strictly")
struct CodexOAuthTests {
    private static let redirect = "http://localhost:1455/auth/callback"

    @Test func `the authorize URL carries the client, PKCE, state and the Codex flags`() throws {
        let url = try #require(URL(string: CodexOAuth.authorizeURL(state: "st4te", challenge: "chal")))
        let items = Dictionary(
            uniqueKeysWithValues: try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                .map { ($0.name, $0.value ?? "") })
        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/oauth/authorize?"))
        #expect(
            items == [
                "response_type": "code", "client_id": "app_EMoamEEZ73f0CkXaXp7hrann", "redirect_uri": Self.redirect,
                "scope": "openid profile email offline_access", "code_challenge": "chal",
                "code_challenge_method": "S256",
                "state": "st4te", "id_token_add_organizations": "true", "codex_cli_simplified_flow": "true",
                "originator": "ask"
            ])
    }

    @Test(arguments: [
        "\(redirect)?code=abcdefghij1&state=S", "abcdefghij1#S", "code=abcdefghij1&state=S",
        "?code=abcdefghij1&state=S",
        "  \(redirect)?state=S&code=abcdefghij1  "
    ])
    func `every form a user may paste yields the code when the state is this sign-in's`(pasted: String) {
        #expect(CodexOAuth.authorizationCode(fromPasted: pasted, expectedState: "S") == "abcdefghij1")
    }

    @Test(arguments: [
        "\(redirect)?code=abcdefghij1&state=other", "\(redirect)?code=abcdefghij1", "abcdefghij1", "abcdefghij1#other",
        "code=abcdefghij1&state=other", "http://evil.example/auth/callback?code=abcdefghij1&state=S",
        "http://localhost:1456/auth/callback?code=abcdefghij1&state=S", "\(redirect)x?code=abcdefghij1&state=S",
        "http://u:p@localhost:1455/auth/callback?code=abcdefghij1&state=S",
        "http://u@localhost:1455/auth/callback?code=abcdefghij1&state=S",
        "http://:p@localhost:1455/auth/callback?code=abcdefghij1&state=S",
        "\(redirect)?code=abcdefghij1&code=zzzzzzzzzz2&state=S", "\(redirect)?code=abcdefghij1&state=S&state=S",
        "\(redirect)?error=access_denied&code=abcdefghij1&state=S", "\(redirect)?code=short&state=S", "", "#",
        "\(redirect)?code=abcdefghij1&state=S" + String(repeating: "a", count: 5000)
    ])
    func `anything else is refused, with no shortcut that skips the state`(pasted: String) {
        #expect(CodexOAuth.authorizationCode(fromPasted: pasted, expectedState: "S") == nil, "\(pasted.prefix(80))")
    }

    @Test func `an empty expected state accepts nothing`() {
        #expect(CodexOAuth.authorizationCode(fromPasted: "abcdefghij1#", expectedState: "") == nil)
    }

    private func jwt(_ claims: String) -> String {
        func part(_ text: String) -> String { Base64URL.encode(Array(text.utf8)) }
        return [part(#"{"alg":"none"}"#), part(claims), "sig"].joined(separator: ".")
    }

    @Test func `the account id is the token's own ChatGPT claim`() {
        let token = jwt(#"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct_123-ABC.x"},"exp":1}"#)
        #expect(CodexOAuth.accountID(inAccessToken: token) == "acct_123-ABC.x")
    }

    @Test(arguments: [
        #"{"exp":1}"#, #"{"https://api.openai.com/auth":{}}"#, #"{"https://api.openai.com/auth":"x"}"#,
        #"{"https://api.openai.com/auth":{"chatgpt_account_id":7}}"#,
        #"{"https://api.openai.com/auth":{"chatgpt_account_id":"has space"}}"#,
        #"{"https://api.openai.com/auth":{"chatgpt_account_id":"a/b"}}"#,
        #"{"https://api.openai.com/auth":{"chatgpt_account_id":""}}"#, "[]", "not json",
        #"{"https://api.openai.com/auth":{"chatgpt_account_id":"\#(String(repeating: "a", count: 129))"}}"#
    ])
    func `a claim that is absent or is not a plain id gives none`(claims: String) {
        #expect(CodexOAuth.accountID(inAccessToken: jwt(claims)) == nil)
    }

    @Test func `a token that is not a three-part JWT gives none`() {
        for token in ["", "a.b", "a.b.c.d", "a.!!!.c", "plain"] {
            #expect(CodexOAuth.accountID(inAccessToken: token) == nil)
        }
    }
}
