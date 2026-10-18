/// Why no request auth could be produced.
public enum ClaudeAccessError: Error, Sendable, Equatable {
    /// Nothing is stored: `ask login` first.
    case signedOut
    /// The stored credentials could not be read.
    case storage(CredentialFileError)
    /// The credentials expired and could not be refreshed. `invalid_grant` means signing in again.
    case refreshFailed(ClaudeAuthError)
}
