public import Foundation

/// The authority a model catalog describes. A catalog from another account or endpoint is never a fallback.
// @dl:accept -- three stored identity fields and their initializer are data shape, not reusable behavior shared with a tool invocation
public struct ModelCatalogScope: Codable, Sendable, Equatable {
    public let provider: String
    public let accountID: String
    public let endpoint: URL

    /// A scope bound to this provider, account and exact catalog endpoint (including its schema-version query).
    public init(provider: String, accountID: String, endpoint: URL) {
        self.provider = provider
        self.accountID = accountID
        self.endpoint = endpoint
    }
}
