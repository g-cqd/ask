/// Why signing in to Codex or refreshing failed. Bodies are never echoed: they can carry secrets.
public enum CodexAuthError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The token endpoint refused, with a standard OAuth error code when it sent one.
    case tokenEndpoint(status: Int, code: String?)
    /// The token endpoint answered 2xx with something that is not sound credentials.
    case invalidResponse
    /// The access token names no ChatGPT account, so inference could not be addressed.
    case noAccountID
    /// The request did not complete.
    case transport(String)

    public var description: String {
        switch self {
            case .tokenEndpoint(let status, let code):
                "the token endpoint refused with status \(status)" + (code.map { " (\($0))" } ?? "")
                    + (Self.spent.contains(code ?? "")
                        ? "; the sign-in is no longer valid, run `ask login codex` again" : "")
            case .invalidResponse: "the token endpoint's answer was not sound credentials"
            case .noAccountID: "the access token names no ChatGPT account"
            case .transport(let detail): "no answer from the token endpoint: \(detail)"
        }
    }

    private static let spent: Set = [
        "invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"
    ]
}
