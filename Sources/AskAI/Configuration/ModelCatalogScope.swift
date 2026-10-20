public import Foundation

/// The authority a model catalog describes. A catalog from another account or endpoint is never a fallback.
// @dl:accept -- three stored identity fields and their initializer are data shape, not reusable behavior shared with a tool invocation
public struct ModelCatalogScope: Codable, Sendable, Equatable {
    public let provider: String
    public let accountID: String
    public let endpoint: URL
    /// Stable named-registration identity; nil retains the legacy default cache format.
    public let connectionID: UUID?

    /// A scope bound to this provider, account and exact catalog endpoint (including its schema-version query).
    public init(provider: String, accountID: String, endpoint: URL, connectionID: UUID? = nil) {
        self.provider = provider
        self.accountID = accountID
        self.endpoint = endpoint
        self.connectionID = connectionID
    }
}
