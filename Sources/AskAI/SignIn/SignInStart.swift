public import Foundation

/// A begun sign-in: the session, the link the user opens, and how long the session may last.
public struct SignInStart<Session: Sendable>: Sendable {
    public let session: Session
    public let url: URL
    public let window: Duration

    /// A begun sign-in.
    public init(session: Session, url: URL, window: Duration) {
        self.session = session
        self.url = url
        self.window = window
    }
}
