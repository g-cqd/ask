internal import Foundation

/// The Antigravity sign-in's fixed addresses and its request. The client id names the application; it is public.
///
/// The authorize request is the one the shipped `agy` prints for its Google sign-in, captured from 1.4.6 in a never-signed-in
/// profile: the same endpoint, client id, redirect and scopes in the same order, parameters in alphabetical order, spaces as `+`.
public enum AgyOAuth {
    public static let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    public static let authorizeEndpoint = "https://accounts.google.com/o/oauth2/auth"
    public static let tokenURL = "https://oauth2.googleapis.com/token"
    /// A hosted page that shows the authorization code for the user to paste back.
    public static let redirectURI = "https://antigravity.google/oauth-callback"
    public static let scopes = [
        "https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile", "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs", "https://www.googleapis.com/auth/aicode", "openid"
    ]

    /// A state value: 16 random bytes, base64url, which is 22 characters as the shipped CLI's is.
    static func newState() -> String {
        var random = SystemRandomNumberGenerator()
        // @dl:accept -- two providers' states differ in width and encoding; the random-bytes loop is one line each
        return Base64URL.encode((0 ..< 16).map { _ in UInt8.random(in: .min ... .max, using: &random) })
    }

    /// The URL the user opens to sign in.
    // @dl:accept -- each provider's authorize address is its own table of parameters; they share a shape by being OAuth
    public static func authorizeURL(state: String, challenge: String) -> String {
        let query: [(String, String)] = [
            // @dl:accept -- the parameter rows are data, and the providers' differ in every value
            ("access_type", "offline"), ("client_id", clientID), ("code_challenge", challenge),
            ("code_challenge_method", "S256"), ("prompt", "consent"), ("redirect_uri", redirectURI),
            ("response_type", "code"), ("scope", scopes.joined(separator: " ")), ("state", state)
        ]
        return authorizeEndpoint + "?" + FormEncoding.query(query)
    }

    private static func isCode(_ text: String) -> Bool { PlainToken.matches(text, length: 10 ... 512, extra: "/_.~-") }

    // @dl:accept -- both parsers open by trimming and bounding the paste before choosing a form; the bounds are each provider's own
    private static func isState(_ text: String) -> Bool { PlainToken.matches(text, length: 1 ... 200, extra: "_.~-") }

    /// The authorization code in what the user pasted, when it is genuine and, if it names a state, carries `expectedState`.
    ///
    /// The hosted page shows the code itself, so a bare code is accepted: PKCE binds it to this sign-in's verifier, and a code from
    /// another flow fails at the exchange. The full redirect URL is accepted from exactly that page, and so is its query alone.
    /// Anything else, an error parameter, two codes, or a state that is not this sign-in's, returns nil.
    public static func authorizationCode(fromPasted pasted: String, expectedState: String) -> String? {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 4_096 else { return nil }
        let parsed: (code: String, state: String?)?
        if PastedAuthorization.hasScheme(text) {
            parsed = fromURL(text)
        } else if text.contains("code=") {
            parsed = fromQuery(String(text.drop { $0 == "?" || $0 == "#" }))
        } else {
            parsed = isCode(text) ? (text, nil) : nil
        }
        guard let parsed, isCode(parsed.code) else { return nil }
        if let state = parsed.state, !isState(state) || state != expectedState { return nil }
        return parsed.code
    }

    private static func fromURL(_ text: String) -> (code: String, state: String?)? {
        let expected = URLComponents(string: redirectURI)
        guard let url = URLComponents(string: text), url.scheme?.lowercased() == "https",
            url.host?.lowercased() == expected?.host, url.port == nil || url.port == 443, url.user == nil,
            url.password == nil, url.path == expected?.path
        else { return nil }
        return PastedAuthorization.codeAndState(in: url.queryItems ?? [])
    }

    private static func fromQuery(_ text: String) -> (code: String, state: String?)? {
        var components = URLComponents()
        components.percentEncodedQuery = text
        return PastedAuthorization.codeAndState(in: components.queryItems ?? [])
    }
}
