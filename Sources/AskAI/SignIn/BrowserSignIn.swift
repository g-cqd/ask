/// A sign-in the user approves in a browser while ask polls for the result.
///
/// Spettro's device sign-in, Mistral Vibe's and Codex's device-code sign-in have this shape, so the waiting, the
/// deadline, the server's pace and cancellation are written once in ``SignInRunner``. A flow carries only its own
/// requests and the checks on what it is told.
public protocol BrowserSignIn: Sendable {
    /// What a flow keeps between start and poll.
    associatedtype Session: Sendable
    /// What a finished poll hands over: a key, or the means of getting credentials.
    associatedtype Grant: Sendable
    /// What the sign-in ends in: a key, or credentials.
    associatedtype Outcome: Sendable

    /// Whether the first poll comes at once, rather than after one interval.
    var pollsImmediately: Bool { get }

    /// Begins a session.
    /// - Returns: the session, what the user is shown, how long it may last and how often to poll.
    func start() async throws(SignInError) -> SignInStart<Session>
    /// Asks whether the user has finished.
    func poll(_ session: Session) async throws(SignInError) -> SignInPoll<Grant>
    /// Turns what a finished poll handed over into what the sign-in ends in.
    func finish(_ session: Session, grant: Grant) async throws(SignInError) -> Outcome
}
