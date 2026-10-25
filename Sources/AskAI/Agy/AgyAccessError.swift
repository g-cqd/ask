/// Why no usable Antigravity session could be produced.
public enum AgyAccessError: Error, Sendable, Equatable, CustomStringConvertible {
    /// Nothing is stored: `ask login agy` first.
    case signedOut
    /// The stored credentials could not be read.
    case storage(CredentialFileError)
    /// Google refused the refresh. `invalid_grant` means signing in again.
    case refreshFailed(AgyAuthError)
    /// A request could not be sent or answered, so nothing is known about the sign-in.
    case unreachable(String)
    /// Google no longer accepts the stored application secret, and the installed `agy` did not give one it accepts.
    case secretUnavailable(String)
    /// Cloud Code onboarding failed.
    case onboarding(AgyCloudError)
    /// The sign-in was replaced while a refresh was waiting for Google, and the replacement itself needs refreshing.
    case changedDuringRefresh

    // @dl:accept -- describing an error enum case by case is the shape of every one; the sentences are its own
    public var description: String {
        switch self {
            case .signedOut: "not signed in to Antigravity: run `ask login agy`"
            // @dl:accept -- describing an error enum case by case is the shape of every one; the sentences are the data
            case .storage(let error): "the stored Antigravity credentials cannot be used: \(error)"
            case .refreshFailed(let error): "the Antigravity sign-in could not be refreshed: \(error)"
            case .unreachable(let reason): "Google could not be reached: \(reason)"
            case .secretUnavailable(let reason):
                "Google no longer accepts the application's stored secret, and a new one could not be found: \(reason)"
            case .onboarding(let error): "\(error)"
            case .changedDuringRefresh:
                "the Antigravity sign-in changed while it was being refreshed; run the command again"
        }
    }
}
