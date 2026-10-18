internal import AemiJSON

/// Everything one model request carries, independent of the provider's wire protocol.
public struct ModelRequest: Sendable, Equatable {
    public var model: String
    public var maxTokens: Int
    /// ask's instructions. Providers decide where they travel; see ``AnthropicRequestEncoder``.
    public var systemPrompt: [String]
    public var messages: [ModelMessage]
    public var tools: [ToolDefinition]

    /// A request with these fields.
    public init(
        model: String, maxTokens: Int, systemPrompt: [String], messages: [ModelMessage], tools: [ToolDefinition]
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
        self.messages = messages
        self.tools = tools
    }
}
