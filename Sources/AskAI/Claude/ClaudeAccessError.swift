/// Why no request auth could be produced.
// @dl:accept -- the two providers' access errors differ in their refresh error and their sentences; one generic type would hide both
public enum ClaudeAccessError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Nothing is stored: `ask login` first.
    case signedOut
    /// The stored credentials could not be read.
    case storage(CredentialFileError)
    /// The credentials expired and could not be refreshed. `invalid_grant` means signing in again.
    case refreshFailed(ClaudeAuthError)
    /// Another ask process held the refresh lock for the whole wait.
    case lockUnavailable
    /// The sign-in was replaced while a refresh was waiting for the server, and the replacement itself needs refreshing.
    case changedDuringRefresh
    /// A named connection's refresh must not change the remote account receiving its history.
    case accountChanged

    // @dl:accept -- describing an error enum case by case is the shape of every one; the sentences are its own
    public var description: String {
        switch self {
            case .signedOut: "not signed in to Claude: run `ask login claude`"
            case .storage(let error): "the stored Claude credentials cannot be used: \(error)"
            case .refreshFailed(let error):
                "the Claude sign-in could not be refreshed (\(error)); run `ask login claude` again"
            case .lockUnavailable: "another ask is refreshing the Claude sign-in and did not finish; try again"
            case .accountChanged: "the refresh returned another account; sign in to the selected named connection again"
            case .changedDuringRefresh: "the Claude sign-in changed while it was being refreshed; run the command again"
        }
    }
}
