internal import CryptoKit
internal import Foundation

/// An RFC 7636 S256 verifier and its challenge. A fresh pair for every sign-in attempt.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    /// The pair for `verifier`.
    public init(verifier: String) {
        self.verifier = verifier
        challenge = Base64URL.encode(Array(SHA256.hash(data: Array(verifier.utf8))))
    }

    /// A pair from 32 bytes of the system's cryptographic random source.
    public static func generate() -> PKCE {
        var random = SystemRandomNumberGenerator()
        return PKCE(verifier: Base64URL.encode((0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &random) }))
    }
}

/// Claude subscription sign-in: the authorize URL, and validation of what the user pastes back.
///
/// Constants and rules are those of the working implementation in pi-integrations, whose sign-ins succeed.
public enum ClaudeOAuth {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeEndpoint = "https://claude.com/cai/oauth/authorize"
    public static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scopes =
        "org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers"
        + " user:file_upload user:plugins"

    /// A state value: 32 random bytes as lowercase hex.
    public static func newState() -> String {
        var random = SystemRandomNumberGenerator()
        return (0 ..< 32)
            .map { _ in
                let byte = UInt8.random(in: .min ... .max, using: &random)
                return String(byte, radix: 16).leftPadded(to: 2)
            }
            .joined()
    }

    /// The URL the user opens to sign in.
    public static func authorizeURL(state: String, challenge: String) -> String {
        let query: [(String, String)] = [
            ("code", "true"), ("client_id", clientID), ("response_type", "code"), ("redirect_uri", redirectURI),
            ("scope", scopes), ("state", state), ("code_challenge", challenge), ("code_challenge_method", "S256")
        ]
        return authorizeEndpoint + "?"
            + query.map { FormEncoding.encode($0) + "=" + FormEncoding.encode($1) }
            .joined(separator: "&")
    }

    /// The authorization code in what the user pasted, when it is genuine and carries `expectedState`.
    ///
    /// Accepted: the callback or success URL of `platform.claude.com` with exactly one code, at most one state
    /// and no error; or exactly one `code#state` token. Anything else, including a state that does not match,
    /// returns nil.
    public static func authorizationCode(fromPasted pasted: String, expectedState: String) -> String? {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        // No check that `expectedState` is nonempty is needed: a parsed state is never empty.
        guard !text.isEmpty, text.utf16.count <= 4_096 else { return nil }
        let parsed = hasScheme(text) ? fromURL(text) : fromToken(text)
        guard let parsed, parsed.state == expectedState else { return nil }
        return parsed.code
    }

    // MARK: - Pasted forms

    private static let tokenCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.~-")

    private static func isToken(_ text: Substring, length: ClosedRange<Int>) -> Bool {
        length.contains(text.count) && text.allSatisfy(tokenCharacters.contains)
    }

    private static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":"), let first = text.first, first.isASCII, first.isLetter else {
            return false
        }
        return text[text.index(after: text.startIndex) ..< colon]
            .allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-")
            }
    }

    private static func fromURL(_ text: String) -> (code: String, state: String?)? {
        guard let url = URLComponents(string: text), url.scheme?.lowercased() == "https",
            url.host?.lowercased() == "platform.claude.com", url.port == nil || url.port == 443,
            url.user == nil, url.password == nil,
            ["/oauth/code/callback", "/oauth/code/success"].contains(url.path)
        else { return nil }
        var fragment = URLComponents()
        fragment.percentEncodedQuery = url.percentEncodedFragment
        let items = (url.queryItems ?? []) + (fragment.queryItems ?? [])
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.map { $0.value ?? "" } }
        let codes = values("code")
        let states = values("state")
        guard codes.count == 1, states.count <= 1, values("error").isEmpty,
            isToken(codes[0][...], length: 10 ... 200)
        else { return nil }
        if let state = states.first, !isToken(state[...], length: 1 ... 200) { return nil }
        return (codes[0], states.first)
    }

    /// Exactly one maximal run of token characters and `#` that is `code#state`, or one bare code.
    private static func fromToken(_ text: String) -> (code: String, state: String?)? {
        let runs = text.split { !(tokenCharacters.contains($0) || $0 == "#") }
        let pairs: [(String, String)] = runs.compactMap { run in
            let parts = run.split(separator: "#", omittingEmptySubsequences: false)
            guard parts.count == 2, isToken(parts[0], length: 20 ... 200), isToken(parts[1], length: 1 ... 200) else {
                return nil
            }
            return (String(parts[0]), String(parts[1]))
        }
        if pairs.count == 1 { return (pairs[0].0, pairs[0].1) }
        if pairs.isEmpty, isToken(text[...], length: 20 ... 200) { return (text, nil) }
        return nil
    }
}

/// `application/x-www-form-urlencoded`, as browsers' `URLSearchParams` writes it.
enum FormEncoding {
    static func encode(_ value: String) -> String {
        var out = ""
        for byte in value.utf8 {
            switch byte {
                case 0x2A, 0x2D, 0x2E, 0x30 ... 0x39, 0x41 ... 0x5A, 0x5F, 0x61 ... 0x7A:
                    out.append(Character(UnicodeScalar(byte)))
                case 0x20: out.append("+")
                default: out += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
            }
        }
        return out
    }
}

/// Unpadded base64url (RFC 4648 §5).
enum Base64URL {
    static func encode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
