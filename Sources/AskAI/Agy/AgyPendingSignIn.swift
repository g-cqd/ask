/// A sign-in in progress: what the user is shown, and what completing it needs.
// @dl:accept -- each provider's pending sign-in differs in its state and URL; a generic type would hide both
public struct AgyPendingSignIn: Sendable, Equatable {
    public let pkce: PKCE
    public let state: String

    /// A sign-in with this verifier and state.
    public init(pkce: PKCE, state: String) {
        self.pkce = pkce
        self.state = state
    }

    /// A fresh sign-in.
    public static func begin() -> AgyPendingSignIn { AgyPendingSignIn(pkce: .generate(), state: AgyOAuth.newState()) }

    /// The URL the user opens.
    public var url: String { AgyOAuth.authorizeURL(state: state, challenge: pkce.challenge) }
}
