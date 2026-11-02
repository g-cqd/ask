/// A sign-in a server's requests carry (roadmap 0067): the header with its current token, renewed before it runs out, and what to do
/// when the server refuses it.
public protocol MCPAuthorization: Sendable {
    /// `Bearer <token>`, or nil when there is none to send.
    func header() async -> String?
    /// The server refused the token (`401`, or `403` asking for more scope): whether a new one is ready, so the request is sent again.
    func refused(_ challenge: MCPAuthChallenge?) async -> Bool
}
