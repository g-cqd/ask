/// A failure the provider reported. Each kind calls for a different response, so none collapse into a string.
public struct ProviderFailure: Error, Sendable, Equatable {
    /// The provider's classification.
    public enum Kind: Sendable, Equatable {
        case overloaded, rateLimited, authentication, permission, invalidRequest, notFound, requestTooLarge, server
        /// The request is longer than the model's context window. Sending it again cannot succeed; compacting
        /// the conversation first can.
        case contextOverflow
        /// A kind this decoder does not know, kept verbatim.
        case other(String)
    }

    public let kind: Kind
    /// The provider's message, for the user.
    public let message: String

    /// The context window the provider said the model has, when a refusal for length names it.
    public let contextWindow: Int?

    /// A failure of this kind.
    public init(kind: Kind, message: String, contextWindow: Int? = nil) {
        self.kind = kind
        self.message = message
        self.contextWindow = contextWindow
    }
}
