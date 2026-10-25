public import AskAI

/// A tool a server offers.
public struct MCPTool: Sendable, Equatable {
    /// The name the server calls it by.
    public let name: String
    /// A name for people, when it has one.
    public let title: String?
    /// What it does, as the server describes it. The server's words, which the model will read.
    public let description: String
    /// The JSON Schema of its arguments, byte for byte as the server sent it (it is spliced into requests, never parsed and written again).
    public let inputSchema: JSONObject
    /// The server's hints.
    public let annotations: MCPToolAnnotations
    /// Whether the server describes the shape of the tool's structured result.
    public let hasOutputSchema: Bool

    /// A tool.
    public init(
        name: String, title: String?, description: String, inputSchema: JSONObject, annotations: MCPToolAnnotations,
        hasOutputSchema: Bool
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.annotations = annotations
        self.hasOutputSchema = hasOutputSchema
    }
}
