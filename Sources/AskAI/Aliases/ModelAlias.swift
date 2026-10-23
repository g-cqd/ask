/// One local name for a server model, with limits the user states, kept apart from what the server reports.
public struct ModelAlias: Codable, Sendable, Equatable {
    /// The server's own model id, within one connection.
    public let model: String
    /// A context window the user states; it wins over the catalog's and is shown as the user's, not the server's.
    public let contextWindow: Int?
    /// A longest reply the user states.
    public let maxOutputTokens: Int?
    /// A thinking level the user chose for this alias; nil leaves the configured one.
    public let thinking: ThinkingLevel?

    /// An alias for `model`.
    public init(model: String, contextWindow: Int? = nil, maxOutputTokens: Int? = nil, thinking: ThinkingLevel? = nil) {
        self.thinking = thinking
        self.model = model
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }
}
