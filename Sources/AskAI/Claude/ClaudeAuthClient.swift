internal import Foundation

/// Completes sign-ins and refreshes credentials against the token endpoint.
public struct ClaudeAuthClient: Sendable {
    private let transport: any HTTPTransport

    /// A client that sends through `transport`.
    public init(transport: any HTTPTransport) { self.transport = transport }

    /// Exchanges the code the user pasted for credentials.
    /// - Throws: ``ClaudeAuthError/invalidPastedCode`` before any request when the paste is not genuine or
    ///   belongs to another sign-in; otherwise a token endpoint or transport error.
    public func complete(_ pending: PendingSignIn, pasted: String, now: Double) async throws(ClaudeAuthError)
        -> ClaudeCredentials
    {
        guard let code = ClaudeOAuth.authorizationCode(fromPasted: pasted, expectedState: pending.state) else {
            throw .invalidPastedCode
        }
        return try await post(
            ClaudeToken.exchangeBody(code: code, verifier: pending.pkce.verifier, state: pending.state), now: now)
    }

    /// New credentials for `credentials`. Account details the response omits are kept.
    /// - Throws: a token endpoint or transport error; `invalid_grant` means signing in again.
    public func refresh(_ credentials: ClaudeCredentials, now: Double) async throws(ClaudeAuthError)
        -> ClaudeCredentials
    {
        var refreshed = try await post(ClaudeToken.refreshBody(refreshToken: credentials.refreshToken), now: now)
        refreshed.accountEmail = refreshed.accountEmail ?? credentials.accountEmail
        refreshed.organizationName = refreshed.organizationName ?? credentials.organizationName
        return refreshed
    }

    private func post(_ body: [UInt8], now: Double) async throws(ClaudeAuthError) -> ClaudeCredentials {
        let request = HTTPRequest(
            url: URL(string: ClaudeOAuth.tokenEndpoint)!, method: "POST",
            headers: [("content-type", "application/json"), ("accept", "application/json"), ("user-agent", "ask")],
            body: body)
        let status: Int
        let response: [UInt8]
        do {
            let reply = try await transport.send(request)
            status = reply.status
            response = try await reply.collect(limit: 64 << 10)
        } catch {
            throw .transport(String(describing: error))
        }
        return try ClaudeToken.credentials(status: status, body: response, now: now)
    }
}
