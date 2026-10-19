/// Why no usable Codex credentials could be produced.
public enum CodexAccessError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Nothing is stored: `ask login codex` first.
    case signedOut
    /// The stored credentials could not be read or written. A failed save after a successful refresh loses the new pair
    /// while the old one is spent, so it needs a new sign-in.
    case storage(CredentialFileError)
    /// The credentials expired and could not be refreshed. `invalid_grant` and the `refresh_token_*` codes mean signing in
    /// again.
    case refreshFailed(CodexAuthError)
    /// Another ask process held the refresh lock for the whole wait.
    case lockUnavailable

    public var description: String {
        switch self {
            case .signedOut: "not signed in to Codex: run `ask login codex`"
            case .storage(let error): "the stored Codex credentials cannot be used: \(error)"
            case .refreshFailed(let error): "the Codex sign-in could not be refreshed: \(error)"
            case .lockUnavailable: "another ask is refreshing the Codex sign-in and did not finish; try again"
        }
    }
}
