/// What an Antigravity sign-in yields. Onboarding adds the project and tier later.
public struct AgyCredentials: Sendable, Equatable, Codable {
    public var accessToken: String
    public var refreshToken: String
    /// Seconds since 1970 after which the access token is renewed.
    public var expiresAt: Double
    public var scopes: String?
    /// Display only, read from the ID token; never used for trust.
    public var accountEmail: String?
    public var projectID: String?
    public var tierID: String?
    /// The application's client secret, found in the user's `agy` and confirmed by Google (ADR-0072), kept so a refresh need not
    /// find it again. Nil in a record an older build wrote.
    public var clientSecret: String?

    /// Credentials with these values.
    public init(
        accessToken: String, refreshToken: String, expiresAt: Double, scopes: String? = nil,
        accountEmail: String? = nil,
        projectID: String? = nil, tierID: String? = nil, clientSecret: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.accountEmail = accountEmail
        self.projectID = projectID
        self.tierID = tierID
        self.clientSecret = clientSecret
    }
}
