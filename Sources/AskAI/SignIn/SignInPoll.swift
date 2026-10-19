/// What one poll of a sign-in found.
public enum SignInPoll: Sendable, Equatable {
    /// The user has not finished in the browser.
    case pending
    /// The user finished; this is what the server handed over: a key, or a token to exchange for one.
    case complete(String)
}
