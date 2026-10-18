internal import Foundation

/// A sign-in in progress: what the user is shown, and what completing it needs.
public struct PendingSignIn: Sendable, Equatable {
    public let pkce: PKCE
    public let state: String

    /// A sign-in with this verifier and state.
    public init(pkce: PKCE, state: String) {
        self.pkce = pkce
        self.state = state
    }

    /// A fresh sign-in.
    public static func begin() -> PendingSignIn { PendingSignIn(pkce: .generate(), state: ClaudeOAuth.newState()) }

    /// The URL the user opens.
    public var url: String { ClaudeOAuth.authorizeURL(state: state, challenge: pkce.challenge) }
}
