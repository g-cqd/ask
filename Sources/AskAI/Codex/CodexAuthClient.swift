internal import AemiJSON
internal import Foundation

/// Completes Codex sign-ins and refreshes credentials against the token endpoint.
///
/// A refresh spends the refresh token, so an uncertain result is reported and never retried here: the server may
/// already have spent it, and a retry would present a token it knows is used.
public struct CodexAuthClient: Sendable {
    private static let errorCodes: Set = [
        "invalid_request", "invalid_client", "invalid_grant", "unauthorized_client", "unsupported_grant_type",
        "invalid_scope", "access_denied", "temporarily_unavailable", "expired_token", "slow_down",
        "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"
    ]

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
        let body = fields.map { FormEncoding.encode($0) + "=" + FormEncoding.encode($1) }.joined(separator: "&")
        let request = HTTPRequest(
            url: URL(string: CodexOAuth.tokenEndpoint)!, method: "POST",
            headers: [
                ("content-type", "application/x-www-form-urlencoded"), ("accept", "application/json"),
                ("user-agent", "ask")
            ], body: Array(body.utf8))
        let status: Int
        let response: [UInt8]
        do {
            let reply = try await transport.send(request)
            status = reply.status
            response = try await reply.collect(limit: 64 << 10)
        } catch {
            throw .transport(String(describing: error))
        }
        guard (200 ..< 300).contains(status) else {
            let code = (try? AemiJSON.JSONDecoder().decode(ErrorBody.self, from: response))?.code
            throw .tokenEndpoint(status: status, code: code.flatMap { Self.errorCodes.contains($0) ? $0 : nil })
        }
        return try credentials(from: response, now: now)
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

    /// An error body, whose `error` is a code or an object holding one.
    private struct ErrorBody: Decodable {
        let code: String?

        private enum Keys: String, CodingKey { case error }
        private enum Nested: String, CodingKey { case code }

        init(from decoder: any Decoder) throws {
            let keys = try decoder.container(keyedBy: Keys.self)
            if let text = try? keys.decode(String.self, forKey: .error) {
                code = text
            } else {
                code = try? keys.nestedContainer(keyedBy: Nested.self, forKey: .error)
                    .decode(String.self, forKey: .code)
            }
        }
    }
}
