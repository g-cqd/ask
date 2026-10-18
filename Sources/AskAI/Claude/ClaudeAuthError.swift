internal import AemiJSON

/// Why signing in or refreshing failed. Bodies are never echoed: they can carry secrets.
public enum ClaudeAuthError: Error, Sendable, Equatable {
    /// The pasted response was not genuine, or its state did not match this sign-in.
    case invalidPastedCode
    /// The token endpoint refused, with a standard OAuth error code when it sent one.
    case tokenEndpoint(status: Int, code: String?)
    /// The token endpoint answered 2xx with something that is not sound credentials.
    case invalidResponse
    /// The request did not complete.
    case transport(String)
}
