/// An API key a provider's browser sign-in issued, as stored: Spettro's device key, a Mistral key from Vibe.
public struct StoredKey: Sendable, Equatable, Codable {
    /// The key itself.
    public let key: String
    /// When it was issued, in seconds since 1970.
    public let obtainedAt: Double

    /// A key issued at `obtainedAt`.
    public init(key: String, obtainedAt: Double) {
        self.key = key
        self.obtainedAt = obtainedAt
    }
}
