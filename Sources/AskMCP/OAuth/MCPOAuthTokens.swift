public import Foundation

/// What a sign-in to a server ends in: the access token sent with each request, the refresh token that renews it, and when it runs out.
public struct MCPOAuthTokens: Sendable, Equatable, Codable {
    public var access: String
    public var refresh: String?
    public var expires: Date?

    /// Tokens with these values.
    public init(access: String, refresh: String?, expires: Date?) {
        self.access = access
        self.refresh = refresh
        self.expires = expires
    }

    /// How long before it runs out a token is renewed, so a request never carries one that ends on the way.
    public static let margin: TimeInterval = 60

    /// Whether it should be renewed before it is used at `now`: it runs out within ``margin``. One without an expiry is used until refused.
    public func isDue(at now: Date) -> Bool {
        guard let expires else { return false }
        return expires.timeIntervalSince(now) < Self.margin
    }
}
