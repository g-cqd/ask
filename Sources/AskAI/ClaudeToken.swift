internal import AemiJSON

/// Claude subscription credentials. `expiresAt` already includes the safety margin.
public struct ClaudeCredentials: Sendable, Equatable, Codable {
    public var accessToken: String
    public var refreshToken: String
    /// Seconds since 1970 after which the access token must be refreshed before use.
    public var expiresAt: Double
    public var refreshExpiresAt: Double?
    public var accountEmail: String?
    public var organizationName: String?
    public var scopes: String

    /// Credentials with these fields.
    public init(
        accessToken: String, refreshToken: String, expiresAt: Double, refreshExpiresAt: Double?,
        accountEmail: String?, organizationName: String?, scopes: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
        self.accountEmail = accountEmail
        self.organizationName = organizationName
        self.scopes = scopes
    }

    /// Whether the access token must be refreshed at `now` (seconds since 1970).
    public func needsRefresh(now: Double) -> Bool { now >= expiresAt }
}

/// Why signing in or refreshing failed. Bodies are never echoed: they can carry secrets.
public enum ClaudeAuthError: Error, Sendable, Equatable {
    /// The pasted response was not genuine, or its state did not match this sign-in.
    case invalidPastedCode
    /// The token endpoint refused, with a standard OAuth error code when it sent one.
    case tokenEndpoint(status: Int, code: String?)
    /// The token endpoint answered 2xx with something that is not sound credentials.
    case invalidResponse
    /// The request did not complete.
    case transport(String)
}

/// Token endpoint bodies and responses.
public enum ClaudeToken {
    private static let oauthErrorCodes: Set = [
        "invalid_request", "invalid_client", "invalid_grant", "unauthorized_client", "unsupported_grant_type",
        "invalid_scope", "access_denied", "temporarily_unavailable"
    ]

    /// The body that exchanges an authorization code.
    public static func exchangeBody(code: String, verifier: String, state: String) -> [UInt8] {
        body([
            ("grant_type", "authorization_code"), ("code", code), ("redirect_uri", ClaudeOAuth.redirectURI),
            ("client_id", ClaudeOAuth.clientID), ("code_verifier", verifier), ("state", state)
        ])
    }

    /// The body that refreshes credentials.
    public static func refreshBody(refreshToken: String) -> [UInt8] {
        body([("grant_type", "refresh_token"), ("refresh_token", refreshToken), ("client_id", ClaudeOAuth.clientID)])
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
        let margin = Swift.min(300, token.expiresIn / 10)
        return ClaudeCredentials(
            accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: now + token.expiresIn - margin,
            refreshExpiresAt: token.refreshTokenExpiresIn.map { now + $0 }, accountEmail: token.account?.emailAddress,
            organizationName: token.organization?.name, scopes: token.scope)
    }

    private static func body(_ fields: [(String, String)]) -> [UInt8] {
        var writer = JSONStreamWriter()
        writer.beginObject()
        for (key, value) in fields {
            writer.key(key)
            writer.string(value)
        }
        writer.endObject()
        return writer.finish()
    }
}

// MARK: - Wire shapes

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
        func validToken(_ value: String) -> Bool {
            !value.isEmpty && value.utf16.count <= 16_384 && !value.contains(where: \.isWhitespace)
        }
        func validLifetime(_ seconds: Double) -> Bool { seconds > 0 && seconds.isFinite && seconds <= 8.64e12 }
        return validToken(accessToken) && validToken(refreshToken) && tokenType.lowercased() == "bearer"
            && validLifetime(expiresIn) && (refreshTokenExpiresIn.map(validLifetime) ?? true)
    }
}
