/// A sign-in that ends in an API key: the user approves in a browser while ask polls for the result.
///
/// Spettro's device sign-in and Mistral Vibe's both have this shape, so the waiting, the deadline and cancellation are
/// written once in ``SignInRunner`` and each flow carries only its own requests and the checks on what it is told.
public protocol BrowserSignIn: Sendable {
    /// What a flow keeps between start and poll.
    associatedtype Session: Sendable

    /// How long to wait between polls.
    var pollInterval: Duration { get }
    /// Whether the first poll comes at once, rather than after one interval.
    var pollsImmediately: Bool { get }

    /// Begins a session.
    /// - Returns: the session, the link for the user, and how long the session may last.
    func start() async throws(SignInError) -> SignInStart<Session>
    /// Asks whether the user has finished.
    func poll(_ session: Session) async throws(SignInError) -> SignInPoll
    /// Turns what a completed poll handed over into the API key. Flows whose poll hands over the key return it.
    func finish(_ session: Session, token: String) async throws(SignInError) -> String
    /// The time to record on the key, in seconds since 1970.
    func timestamp() -> Double
}

extension BrowserSignIn {
    public func finish(_ session: Session, token: String) async throws(SignInError) -> String { token }
}
