/// The model a request will name, after any alias is resolved, and why.
public struct ModelChoice: Sendable, Equatable {
    /// The server's model id: what is sent, and what a session records.
    public let model: String
    /// The alias the user typed, when there was one.
    public let alias: String?
    /// The user's stated window, when the alias gave one.
    public let contextWindow: Int?
    /// The user's stated reply limit, when the alias gave one.
    public let maxOutputTokens: Int?

    /// A choice of `model`.
    public init(model: String, alias: String? = nil, contextWindow: Int? = nil, maxOutputTokens: Int? = nil) {
        self.model = model
        self.alias = alias
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }
}
