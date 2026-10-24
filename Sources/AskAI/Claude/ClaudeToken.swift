internal import AemiJSON

/// Token endpoint bodies and responses.
public enum ClaudeToken {
    private static let oauthErrorCodes: Set = [
        "invalid_request", "invalid_client", "invalid_grant", "unauthorized_client", "unsupported_grant_type",
        "invalid_scope", "access_denied", "temporarily_unavailable"
    ]

    /// The body that exchanges an authorization code.
    public static func exchangeBody(code: String, verifier: String, state: String) -> [UInt8] {
        JSONStreamWriter.object(of: [
            ("grant_type", "authorization_code"), ("code", code), ("redirect_uri", ClaudeOAuth.redirectURI),
            ("client_id", ClaudeOAuth.clientID), ("code_verifier", verifier), ("state", state)
        ])
    }

    /// The body that refreshes credentials.
    public static func refreshBody(refreshToken: String) -> [UInt8] {
        JSONStreamWriter.object(of: [
            ("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", ClaudeOAuth.clientID)
        ])
    }

    /// Credentials from a token endpoint response received at `now` (seconds since 1970).
    /// - Throws: ``ClaudeAuthError/tokenEndpoint(status:code:)`` for a non-2xx status, or
    ///   ``ClaudeAuthError/invalidResponse`` unless every field is sound.
    public static func credentials(status: Int, body: [UInt8], now: Double) throws(ClaudeAuthError) -> ClaudeCredentials
    {
        guard (200 ..< 300).contains(status) else {
            let code = (try? AemiJSON.JSONDecoder().decode(ErrorBody.self, from: body))?.error
            throw .tokenEndpoint(status: status, code: code.flatMap { oauthErrorCodes.contains($0) ? $0 : nil })
        }
        guard let token = try? AemiJSON.JSONDecoder().decode(TokenBody.self, from: body), token.isSound else {
            throw .invalidResponse
        }
        return ClaudeCredentials(
            accessToken: token.accessToken, refreshToken: token.refreshToken,
            expiresAt: TokenSanity.renewal(from: now, lifetime: token.expiresIn),
            refreshExpiresAt: token.refreshTokenExpiresIn.map { now + $0 }, accountEmail: token.account?.emailAddress,
            organizationName: token.organization?.name, scopes: token.scope)
    }

    private struct ErrorBody: Decodable {
        let error: String?
    }

    private struct TokenBody: Decodable {
        struct Account: Decodable {
            let emailAddress: String?
            enum CodingKeys: String, CodingKey { case emailAddress = "email_address" }
        }

        struct Organization: Decodable {
            let name: String?
        }

        let tokenType: String
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let scope: String
        let refreshTokenExpiresIn: Double?
        let account: Account?
        let organization: Organization?

        enum CodingKeys: String, CodingKey {
            case scope, account, organization
            case tokenType = "token_type"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case refreshTokenExpiresIn = "refresh_token_expires_in"
        }

        /// The checks the working implementation applies: bearer tokens of sane size without whitespace, and
        /// positive, finite lifetimes that fit a date.
        var isSound: Bool {
            TokenSanity.isToken(accessToken) && TokenSanity.isToken(refreshToken) && tokenType.lowercased() == "bearer"
                && TokenSanity.isLifetime(expiresIn) && (refreshTokenExpiresIn.map(TokenSanity.isLifetime) ?? true)
        }
    }
}

// MARK: - Wire shapes
