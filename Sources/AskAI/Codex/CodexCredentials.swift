/// Codex subscription credentials. `expiresAt` already includes the safety margin.
///
/// The refresh token rotates and is single use: a refresh returns a whole new pair, and the pair is stored whole.
public struct CodexCredentials: Sendable, Equatable, Codable {
    public var accessToken: String
    public var refreshToken: String
    /// Seconds since 1970 after which the access token must be refreshed before use.
    public var expiresAt: Double
    /// The ChatGPT account the inference backend is addressed by, read from the access token.
    public var accountID: String

    /// Credentials with these fields.
    public init(accessToken: String, refreshToken: String, expiresAt: Double, accountID: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountID = accountID
    }

    /// Whether the access token must be refreshed at `now` (seconds since 1970).
    public func needsRefresh(now: Double) -> Bool { now >= expiresAt }
}
