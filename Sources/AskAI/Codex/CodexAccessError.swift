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
    /// The sign-in was replaced while a refresh was waiting for the server, and the replacement itself needs refreshing.
    case changedDuringRefresh
    /// A named connection's refresh must not change the remote account receiving its history.
    case accountChanged

    // @dl:accept -- describing an error enum case by case is the shape of every one; the sentences are its own
    public var description: String {
        switch self {
            case .signedOut: "not signed in to Codex: run `ask login codex`"
            case .storage(let error): "the stored Codex credentials cannot be used: \(error)"
            case .refreshFailed(let error): "the Codex sign-in could not be refreshed: \(error)"
            case .lockUnavailable: "another ask is refreshing the Codex sign-in and did not finish; try again"
            case .accountChanged: "the refresh returned another account; sign in to the selected named connection again"
            case .changedDuringRefresh: "the Codex sign-in changed while it was being refreshed; run the command again"
        }
    }
}
