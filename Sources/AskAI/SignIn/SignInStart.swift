public import Foundation

/// A begun sign-in: the session, what the user is shown, how long the session may last and how often to poll it.
public struct SignInStart<Session: Sendable>: Sendable {
    public let session: Session
    public let url: URL
    public let window: Duration
    /// How long to wait between polls.
    public let interval: Duration
    /// What to do at the link, such as a code to enter, when the link alone is not enough.
    public let instructions: String?

    /// A begun sign-in.
    public init(session: Session, url: URL, window: Duration, interval: Duration, instructions: String? = nil) {
        self.session = session
        self.url = url
        self.window = window
        self.interval = interval
        self.instructions = instructions
    }
}
