/// What one poll of a sign-in found, with `Grant` the thing a finished sign-in hands over.
public enum SignInPoll<Grant: Sendable>: Sendable {
    /// The user has not finished in the browser.
    case pending
    /// The server asks for polls to be further apart: each one adds five seconds to every wait after it.
    case slowDown
    /// The user finished; this is what the server handed over: a key, or the means of getting one.
    case complete(Grant)
}

extension SignInPoll: Equatable where Grant: Equatable {}
