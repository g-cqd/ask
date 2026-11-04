public import AskAI
internal import AskAgentCore
public import AskMCP
public import Foundation
internal import Synchronization

/// Signing in to a remote server that needs it (roadmap 0067): what it asked for, the sign-in, and connecting it again.
extension MCPHub {
    /// What `name` asked for when it refused for want of a sign-in; nil when it did not.
    public func signInChallenge(for name: String) -> MCPAuthChallenge? {
        state.withLock { $0.host }?.challenge(for: name)
    }

    /// Connects `name` again, as after a sign-in, leaving the others as they are.
    public func reconnect(_ name: String) async {
        await state.withLock { $0.host }?.reconnect(name)
    }

    /// Signs in to the remote server `name` and connects it again.
    /// - Parameters:
    ///   - name: the server, as configured.
    ///   - file: where the sign-in is kept.
    ///   - http: how the authorization server is reached.
    ///   - opening: shown the address to approve, and opens it.
    /// - Throws: ``MCPOAuthError`` saying which step failed, or that `name` is no remote server.
    public func signIn(
        _ name: String,
        file: CredentialFile,
        http: any HTTPTransport,
        opening: @Sendable (URL) async -> Void
    ) async throws(MCPOAuthError) {
        guard let server = state.withLock({ $0.servers.first { $0.name == name } }) else {
            throw MCPOAuthError("there is no MCP server called \(name)")
        }
        guard let address = server.url, let url = URL(string: address) else {
            throw MCPOAuthError("\(name) is a program, not a remote server: it has nothing to sign in to")
        }
        try await MCPSignInFlow(http: http, file: file)
            .signIn(url: url, challenge: signInChallenge(for: name), clientID: server.oauthClientID, opening: opening)
        await reconnect(name)
    }
}
