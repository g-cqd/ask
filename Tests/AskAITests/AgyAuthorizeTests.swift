internal import Foundation
internal import Testing

@testable import AskAI

/// The sign-in's request and what the user pastes back. The authorize request was captured from the real `agy` 1.4.6 in a
/// never-signed-in profile (diary 2026-10-23-16): the same endpoint, client id, redirect and scopes in the same order, parameters
/// in alphabetical order, spaces written as `+`, a 43-character challenge and a 22-character state.
struct AgyAuthorizeTests {
    private static let state = "AbCdEfGhIjKlMnOpQrStUv"
    private static let challenge = "taGH1r3w0_lwD9h40Rjq_4tGEaLqVK7q5GjpVQ_Q6HI"

    @Test func `the authorize URL is the one the shipped CLI prints, parameter for parameter`() {
        let expected =
            "https://accounts.google.com/o/oauth2/auth?access_type=offline"
            + "&client_id=1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
            + "&code_challenge=\(Self.challenge)&code_challenge_method=S256&prompt=consent"
            + "&redirect_uri=https%3A%2F%2Fantigravity.google%2Foauth-callback&response_type=code"
            + "&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcloud-platform"
            + "+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.email"
            + "+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.profile"
            + "+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fcclog"
            + "+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fexperimentsandconfigs"
            + "+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Faicode+openid&state=\(Self.state)"
        #expect(AgyOAuth.authorizeURL(state: Self.state, challenge: Self.challenge) == expected)
    }

    @Test func `a fresh sign-in has its own verifier and a 22-character URL-safe state each time`() {
        let first = AgyPendingSignIn.begin()
        let second = AgyPendingSignIn.begin()
        #expect(first.state != second.state && first.pkce.verifier != second.pkce.verifier)
        #expect(
            first.state.count == 22
                && first.state.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        #expect(
            first.url.contains("state=\(first.state)") && first.url.contains("code_challenge=\(first.pkce.challenge)"))
        #expect(!first.url.contains(first.pkce.verifier))
    }

    private func parse(_ pasted: String) -> String? {
        AgyOAuth.authorizationCode(fromPasted: pasted, expectedState: Self.state)
    }

    @Test(arguments: [
        "4/0AeaYSHDq-abcdefghij_KLMNOP", "  4/0AeaYSHDq-abcdefghij_KLMNOP\n", "abcdefghij",
        String(repeating: "a", count: 512)
    ])
    func `a bare code, which the hosted page shows, is accepted`(_ pasted: String) {
        #expect(parse(pasted) == pasted.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func `the full redirect URL is accepted, and its state must be this sign-in's`() {
        let base = "https://antigravity.google/oauth-callback?code=4/0AeaYSHDqabcdefg"
        #expect(parse(base + "&state=\(Self.state)") == "4/0AeaYSHDqabcdefg")
        #expect(parse(base) == "4/0AeaYSHDqabcdefg", "no state at all is a bare code in a URL, bound by PKCE")
        #expect(parse(base + "&state=another-state-value") == nil)
        #expect(parse(base + "&state=\(Self.state)&state=\(Self.state)") == nil)
    }

    @Test func `the query form of a callback is accepted with the same rules`() {
        #expect(parse("code=4/0AeaYSHDqabcdefg&state=\(Self.state)") == "4/0AeaYSHDqabcdefg")
        #expect(parse("?code=4/0AeaYSHDqabcdefg") == "4/0AeaYSHDqabcdefg")
        #expect(parse("code=4/0AeaYSHDqabcdefg&state=wrong") == nil)
        #expect(parse("code=a&code=b") == nil)
    }

    private static let page = "antigravity.google/oauth-callback"
    private static let code = "code=4/0AeaYSHDqabcdefg"
    private static let wrongPlace = [
        "http://\(page)?\(code)", "https://evil.example/oauth-callback?\(code)",
        "https://antigravity.google.evil.example/oauth-callback?\(code)",
        "https://antigravity.google:8443/oauth-callback?\(code)",
        "https://antigravity.google/other?\(code)"
    ]
    private static let withCredentials = [
        "https://user:pw@\(page)?\(code)", "https://user@\(page)?\(code)", "https://:pw@\(page)?\(code)"
    ]
    private static let wrongParameters = [
        "https://\(page)?\(code)&error=access_denied", "https://\(page)?error=access_denied",
        "https://\(page)?\(code)&code=4/0Bbbbbbbbbbbb", "https://\(page)", "javascript:alert(1)", "file:///etc/passwd"
    ]

    @Test(arguments: wrongPlace + withCredentials + wrongParameters)
    func `a URL from anywhere else, or with an error or two codes, is refused`(_ pasted: String) {
        #expect(parse(pasted) == nil)
    }

    @Test(arguments: [
        "", "   ", "short", "has space inside code1234", "quote\"inside1234567", "semi;colon12345",
        "tab\tinside1234567", "new\nline12345678"
    ])
    func `text that is not a code is refused`(_ pasted: String) {
        #expect(parse(pasted) == nil)
    }

    @Test func `an oversized paste is refused before anything else`() {
        #expect(parse(String(repeating: "a", count: 513)) == nil)
        #expect(parse("https://antigravity.google/oauth-callback?code=" + String(repeating: "a", count: 5_000)) == nil)
        let valid = "https://antigravity.google/oauth-callback?code=4/0AeaYSHDqabcdefg"
        #expect(parse(valid) == "4/0AeaYSHDqabcdefg")
        #expect(
            parse(valid + "&padding=" + String(repeating: "x", count: 5_000)) == nil,
            "a good code does not excuse an oversized paste")
    }
}
