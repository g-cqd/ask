import Testing

@testable import AskAI

/// Claude subscription sign-in: PKCE, the authorize URL, and what a pasted response may be.
///
/// Expected values come from probes, not from memory. The challenge is RFC 7636 Appendix B. The URL and
/// every pasted-response verdict were produced by pi-integrations' working implementation
/// (`src/domains/claude/oauth.ts`, run on 2026-10-18).
@Suite("Claude sign-in builds the exact URL and accepts only a genuine pasted response")
struct ClaudeOAuthTests {
    @Test func `the challenge is the base64url SHA-256 of the verifier`() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func `fresh values are unpadded base64url and hex of 32 random bytes`() {
        let pkce = PKCE.generate()
        #expect(pkce.verifier.count == 43)
        #expect(pkce.verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(PKCE.generate().verifier != pkce.verifier)
        let state = ClaudeOAuth.newState()
        #expect(state.count == 64)
        #expect(state.allSatisfy { $0.isHexDigit })
    }

    @Test func `the authorize URL matches the working implementation byte for byte`() {
        let url = ClaudeOAuth.authorizeURL(state: "0123abcd", challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(
            url == "https://claude.com/cai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"
                + "&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback"
                + "&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference+user%3Asessions%3Aclaude_code"
                + "+user%3Amcp_servers+user%3Afile_upload+user%3Aplugins&state=0123abcd"
                + "&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256")
    }

    @Test(arguments: [
        ("AbCdEfGhIjKlMnOpQrStUv#0123abcd", true),
        ("https://platform.claude.com/oauth/code/callback?code=AbCdEfGhIjKlMnOpQrStUv&state=0123abcd", true),
        ("  AbCdEfGhIjKlMnOpQrStUv#0123abcd  ", true),
        ("https://platform.claude.com/oauth/code/success#code=AbCdEfGhIjKlMnOpQrStUv&state=0123abcd", true),
        ("AbCdEfGhIjKlMnOpQrStUv#wrong", false),
        ("short#0123abcd", false),
        ("https://evil.example/oauth/code/callback?code=AbCdEfGhIjKlMnOpQrStUv&state=0123abcd", false),
        ("AbCdEfGhIjKlMnOpQrStUv", false),
        ("https://platform.claude.com/oauth/code/callback?code=AbCdEfGhIjKlMnOpQrStUv&state=0123abcd&error=x", false),
        ("a AbCdEfGhIjKlMnOpQrStUv#0123abcd b AbCdEfGhIjKlMnOpQrStUw#0123abcd", false),
        ("https://user:pw@platform.claude.com/oauth/code/callback?code=AbCdEfGhIjKlMnOpQrStUv&state=0123abcd", false),
        ("https://user@platform.claude.com/oauth/code/callback?code=AbCdEfGhIjKlMnOpQrStUv&state=0123abcd", false),
        (
            "https://platform.claude.com/oauth/code/callback?code=AbCdEfGhIjKlMnOpQrStUv&code=AbCdEfGhIjKlMnOpQrStUv"
                + "&state=0123abcd", false
        ),
        ("xAbCdEfGhIjKlMnOpQrStUv#0123abcd#extra", false)
    ])
    func `a pasted response is accepted exactly when the working implementation accepts it`(
        pasted: String, accepted: Bool
    ) {
        let code = ClaudeOAuth.authorizationCode(fromPasted: pasted, expectedState: "0123abcd")
        #expect((code == "AbCdEfGhIjKlMnOpQrStUv") == accepted)
        #expect(accepted || code == nil)
    }

    @Test func `an empty expected state accepts nothing, and oversized input is refused`() {
        #expect(ClaudeOAuth.authorizationCode(fromPasted: "AbCdEfGhIjKlMnOpQrStUv#", expectedState: "") == nil)
        // Length is checked after trimming, as in the working implementation, so the padding is not whitespace.
        let huge = "AbCdEfGhIjKlMnOpQrStUv#0123abcd " + String(repeating: "z ", count: 2_050)
        #expect(ClaudeOAuth.authorizationCode(fromPasted: huge, expectedState: "0123abcd") == nil)
    }
}
