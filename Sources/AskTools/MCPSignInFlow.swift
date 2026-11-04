internal import AskAI
internal import AskMCP
internal import Foundation

/// Signs ask in to a remote MCP server (MCP 2025-11-25, Authorization; roadmap 0067): discovery, ask's client id (configured, kept from
/// an earlier sign-in to the same authorization server, or registered now), the browser's approval with PKCE, back to this machine,
/// and the tokens saved in the credential file.
struct MCPSignInFlow: Sendable {
    let http: any HTTPTransport
    let file: CredentialFile

    /// Where the browser comes back to.
    static let callbackPath = "/callback"
    /// The port a configured client id's redirect uses: `http://127.0.0.1:33418/callback` is what to register with the server.
    static let configuredPort: UInt16 = 33418
    /// How long the person has to approve in the browser.
    static let deadline = Duration.seconds(300)

    /// Signs in to the server at `url`.
    /// - Parameters:
    ///   - url: the server's address.
    ///   - challenge: what its refusal asked for, if it refused.
    ///   - configured: `mcp.<server>.oauth.clientId`, when the person set one.
    ///   - opening: shown the address to approve, and opens it.
    /// - Throws: ``MCPOAuthError`` saying which step failed.
    func signIn(
        url: URL,
        challenge: MCPAuthChallenge?,
        clientID configured: String?,
        opening: @Sendable (URL) async -> Void
    ) async throws(MCPOAuthError) {
        let plan = try await MCPOAuthDiscovery.discover(server: url, challenge: challenge, http: http)
        let client = MCPOAuthClient(plan: plan, http: http)
        let kept = ((try? file.loadMCP(server: plan.resource)) ?? nil)
            .flatMap {
                $0.issuer == plan.issuer.absoluteString ? $0 : nil
            }
        var clientID = configured ?? kept?.clientID
        let port =
            configured != nil
            ? Self.configuredPort : kept.flatMap { URL(string: $0.redirectURI)?.port }.flatMap { UInt16(exactly: $0) }
        var listener = port.flatMap { try? LoopbackListener.bind(port: $0) }
        if listener == nil {
            // A configured client's port must be free: its redirect is registered as it is.
            guard configured == nil else {
                throw MCPOAuthError("port \(Self.configuredPort) is in use; free it and sign in again")
            }
            listener = try? LoopbackListener.bind(port: 0)
            clientID = nil
        }
        guard let listener else { throw MCPOAuthError("no port on this machine could take the browser's return") }
        defer { listener.close() }
        let redirect = "http://127.0.0.1:\(listener.port)\(Self.callbackPath)"
        let id: String
        if let clientID { id = clientID } else { id = try await client.register(redirectURI: redirect) }
        let pkce = PKCE.generate()
        let state = PKCE.generate().verifier
        let address = try client.authorizationURL(clientID: id, redirectURI: redirect, pkce: pkce, state: state)
        await opening(address)
        let code = try await Self.approval(listener, state: state)
        let tokens = try await client.exchange(code: code, clientID: id, redirectURI: redirect, pkce: pkce)
        let record = MCPServerCredentials(
            server: plan.resource,
            issuer: plan.issuer.absoluteString,
            tokenEndpoint: plan.tokenEndpoint.absoluteString,
            clientID: id,
            redirectURI: redirect,
            accessToken: tokens.access,
            refreshToken: tokens.refresh ?? "",
            expiresAt: tokens.expires?.timeIntervalSince1970
        )
        do { try file.saveMCP(record) } catch { throw MCPOAuthError("the sign-in could not be saved: \(error)") }
    }

    /// The code the browser brings back, or why none came within ``deadline``.
    private static func approval(_ listener: LoopbackListener, state: String) async throws(MCPOAuthError) -> String {
        let stopper = Task {
            do { try await Task.sleep(for: deadline) } catch { return }
            listener.close()
        }
        defer { stopper.cancel() }
        do {
            return try await listener.authorization(path: callbackPath, state: state)
        } catch .cancelled {
            throw MCPOAuthError("no approval came back within \(deadline.components.seconds / 60) minutes")
        } catch {
            throw MCPOAuthError("the authorization server refused: \(error)")
        }
    }
}
