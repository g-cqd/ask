internal import AemiJSON
internal import Foundation

/// Codex's sign-in against ChatGPT's authorization server: the constants, the address the user opens, and the reading
/// of what comes back.
///
/// This is the Codex CLI's own sign-in, using its public client id; it is not a published third-party contract and may
/// change. Constants and rules follow pi-integrations' working implementation, whose sign-ins succeed. The account id the
/// inference backend needs is read from the access token's own claim.
public enum CodexOAuth {
    public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    public static let authorizeEndpoint = "https://auth.openai.com/oauth/authorize"
    public static let tokenEndpoint = "https://auth.openai.com/oauth/token"
    public static let callbackPort: UInt16 = 1455
    public static let callbackPath = "/auth/callback"
    public static let redirectURI = "http://localhost:\(callbackPort)\(callbackPath)"
    public static let scope = "openid profile email offline_access"
    /// Names this client to the authorization server.
    public static let originator = "ask"

    /// The address the user opens to sign in.
    public static func authorizeURL(state: String, challenge: String) -> String {
        let query: [(String, String)] = [
            ("response_type", "code"), ("client_id", clientID), ("redirect_uri", redirectURI), ("scope", scope),
            ("code_challenge", challenge), ("code_challenge_method", "S256"), ("state", state),
            ("id_token_add_organizations", "true"), ("codex_cli_simplified_flow", "true"), ("originator", originator)
        ]
        // %20, not the form encoding's "+": a space in a query is valid that way to every parser.
        return authorizeEndpoint + "?" + FormEncoding.query(query, spaceAs: "%20")
    }

    /// The authorization code in what a user pasted after signing in, when the callback listener was unavailable: the
    /// whole redirect address, `code#state`, or `code=…&state=…`. The state must be this sign-in's in every form; there is
    /// no bare-code shortcut.
    public static func authorizationCode(fromPasted pasted: String, expectedState: String) -> String? {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4096 else { return nil }
        let pair: (code: String, state: String)?
        if text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil {
            pair = redirected(text)
        } else if text.contains("code=") {
            pair = queried(text.trimmingCharacters(in: CharacterSet(charactersIn: "?#")))
        } else {
            let halves = text.split(separator: "#", omittingEmptySubsequences: false)
            pair = halves.count == 2 ? (String(halves[0]), String(halves[1])) : nil
        }
        guard let pair, pair.state == expectedState, fits(pair.code, 10 ... 512), fits(pair.state, 1 ... 200) else {
            return nil
        }
        return pair.code
    }

    /// The ChatGPT account id in an access token, or nil when the claim is absent or not a plain id.
    ///
    /// The token is not verified: it is read only for the routing claim, from a token the server has just issued over TLS,
    /// and never to decide trust.
    public static func accountID(inAccessToken token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let bytes = Base64URL.decode(String(parts[1])),
            let claims = try? AemiJSON.JSONDecoder().decode(Claims.self, from: bytes),
            let id = claims.auth?.accountID,
            PlainToken.matches(id, length: 1 ... 128, extra: "._-")
        else { return nil }
        return id
    }

    // MARK: - Pasted forms

    /// `user` is non-nil whenever there is any userinfo, a password included, so it alone refuses `u:p@host`.
    private static func redirected(_ text: String) -> (code: String, state: String)? {
        guard let components = URLComponents(string: text), components.scheme == "http", components.host == "localhost",
            components.port == Int(callbackPort), components.path == callbackPath, components.user == nil,
            components.fragment == nil || components.fragment == ""
        else { return nil }
        return queried(components.percentEncodedQuery ?? "")
    }

    private static func queried(_ query: String) -> (code: String, state: String)? {
        guard let items = QueryString.items(in: query), !items.contains(where: { $0.name == "error" }),
            let code = QueryString.value(of: "code", in: items), let state = QueryString.value(of: "state", in: items)
        else { return nil }
        return (code, state)
    }

    private static func fits(_ value: String, _ length: ClosedRange<Int>) -> Bool {
        PlainToken.matches(value, length: length, extra: "_.~-")
    }

    private struct Claims: Decodable {
        struct Auth: Decodable {
            let accountID: String?
            enum CodingKeys: String, CodingKey { case accountID = "chatgpt_account_id" }
        }

        let auth: Auth?
        enum CodingKeys: String, CodingKey { case auth = "https://api.openai.com/auth" }
    }
}
