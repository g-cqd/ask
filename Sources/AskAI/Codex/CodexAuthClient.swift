internal import AemiJSON
internal import Foundation

/// Completes Codex sign-ins and refreshes credentials against the token endpoint.
///
/// A refresh spends the refresh token, so an uncertain result is reported and never retried here: the server may
/// already have spent it, and a retry would present a token it knows is used.
public struct CodexAuthClient: Sendable {
    // @dl:accept -- a table of the OAuth error words this endpoint may name; tables share a shape by being tables
    private static let errorCodes: Set<String> = CodexAuthError.signInEnded.union([
        "invalid_request", "invalid_client", "unauthorized_client", "unsupported_grant_type", "invalid_scope",
        "access_denied", "temporarily_unavailable", "expired_token", "slow_down"
    ])

    private let transport: any HTTPTransport

    /// A client that sends through `transport`.
    public init(transport: any HTTPTransport) { self.transport = transport }

    /// Exchanges an authorization code for credentials.
    /// - Parameters:
    ///   - code: the authorization code.
    ///   - verifier: the PKCE verifier whose challenge started the sign-in.
    ///   - redirectURI: the address the code was issued for.
    ///   - now: the time, in seconds since 1970.
    /// - Returns: the credentials.
    /// - Throws: a ``CodexAuthError``.
    public func exchange(code: String, verifier: String, redirectURI: String, now: Double) async throws(CodexAuthError)
        -> CodexCredentials
    {
        try await post(
            [
                ("grant_type", "authorization_code"), ("client_id", CodexOAuth.clientID), ("code", code),
                ("code_verifier", verifier), ("redirect_uri", redirectURI)
            ], now: now)
    }

    /// The replacement for `credentials`, whose refresh token is spent by the attempt.
    /// - Parameters:
    ///   - credentials: the credentials to refresh.
    ///   - now: the time, in seconds since 1970.
    /// - Returns: a whole new pair.
    /// - Throws: a ``CodexAuthError``; `invalid_grant` and the `refresh_token_*` codes mean signing in again.
    public func refresh(_ credentials: CodexCredentials, now: Double) async throws(CodexAuthError) -> CodexCredentials {
        try await post(
            [
                ("grant_type", "refresh_token"), ("refresh_token", credentials.refreshToken),
                ("client_id", CodexOAuth.clientID)
            ], now: now)
    }

    private func post(_ fields: [(String, String)], now: Double) async throws(CodexAuthError) -> CodexCredentials {
        let body = FormEncoding.query(fields)
        let request = HTTPRequest.account(
            "POST", URL(string: CodexOAuth.tokenEndpoint)!, contentType: "application/x-www-form-urlencoded",
            body: Array(body.utf8))
        let reply: (status: Int, body: [UInt8])
        do { reply = try await transport.collecting(request) } catch { throw .transport(String(describing: error)) }
        guard (200 ..< 300).contains(reply.status) else {
            let code = CodexErrorBody.code(in: reply.body)
            throw .tokenEndpoint(status: reply.status, code: code.flatMap { Self.errorCodes.contains($0) ? $0 : nil })
        }
        return try credentials(from: reply.body, now: now)
    }

    private func credentials(from body: [UInt8], now: Double) throws(CodexAuthError) -> CodexCredentials {
        guard let token = try? AemiJSON.JSONDecoder().decode(TokenBody.self, from: body),
            SignInSecret.isValid(token.accessToken), SignInSecret.isValid(token.refreshToken), token.expiresIn.isFinite,
            token.expiresIn > 0
        else { throw .invalidResponse }
        guard let account = CodexOAuth.accountID(inAccessToken: token.accessToken) else { throw .noAccountID }
        let margin = Swift.min(300, token.expiresIn / 10)
        return CodexCredentials(
            accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: now + token.expiresIn - margin,
            accountID: account)
    }

    private struct TokenBody: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}
