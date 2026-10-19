public import Foundation

/// Codex's browser sign-in: PKCE and a redirect back to this machine, the way the Codex CLI signs in.
///
/// ask listens on port 1455, shows the address to open, and waits for the redirect. When the port is taken (the Codex CLI
/// is signing in at the same moment) or nothing can listen, the user pastes the address the browser ended on instead;
/// the state must match in either case. The port is free again the moment the wait ends.
public struct CodexBrowserSignIn: Sendable {
    private let auth: CodexAuthClient
    private let now: @Sendable () -> Double
    private let bind: @Sendable (UInt16) throws(LoopbackError) -> LoopbackListener

    /// A sign-in over `transport`. `bind` starts the listener; a test supplies its own.
    public init(
        transport: any HTTPTransport, now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
        bind: @escaping @Sendable (UInt16) throws(LoopbackError) -> LoopbackListener = {
            try LoopbackListener.bind(port: $0)
        }
    ) {
        auth = CodexAuthClient(transport: transport)
        self.now = now
        self.bind = bind
    }

    /// Signs in.
    /// - Parameters:
    ///   - show: called once with the address to open and what to do.
    ///   - paste: asked for the address the browser ended on, when nothing could listen; nil means none will come.
    /// - Returns: the credentials.
    /// - Throws: ``SignInError``; ``SignInError/cancelled`` when the task is cancelled or no address will be pasted.
    public func run(show: @Sendable (SignInPrompt) -> Void, paste: @Sendable () async -> String?)
        async throws(SignInError)
        -> CodexCredentials
    {
        let pkce = PKCE.generate()
        let state = SignInState.random()
        let listener = try? bind(CodexOAuth.callbackPort)
        guard let link = URL(string: CodexOAuth.authorizeURL(state: state, challenge: pkce.challenge)) else {
            throw .invalidResponse("authorize address")
        }
        let how =
            listener == nil
            ? "Sign in, then paste the address your browser ends on (it starts with \(CodexOAuth.redirectURI))."
            : "Open the address above in a browser and sign in; ask continues by itself when you are done."
        show(SignInPrompt(url: link, instructions: how))
        let code: String
        if let listener {
            code = try await listener.authorization(path: CodexOAuth.callbackPath, state: state)
        } else {
            guard let pasted = await paste() else { throw .cancelled }
            guard let accepted = CodexOAuth.authorizationCode(fromPasted: pasted, expectedState: state) else {
                throw .invalidResponse("pasted address")
            }
            code = accepted
        }
        do {
            return try await auth.exchange(
                code: code, verifier: pkce.verifier, redirectURI: CodexOAuth.redirectURI, now: now())
        } catch { throw SignInError(error) }
    }
}
