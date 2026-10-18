/// A failure the provider reported. Each kind calls for a different response, so none collapse into a string.
public struct ProviderFailure: Error, Sendable, Equatable {
    /// The provider's classification.
    public enum Kind: Sendable, Equatable {
        case overloaded, rateLimited, authentication, permission, invalidRequest, notFound, requestTooLarge, server
        /// A kind this decoder does not know, kept verbatim.
        case other(String)
    }

    public let kind: Kind
    /// The provider's message, for the user.
    public let message: String

    /// A failure of this kind.
    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }
}
