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
