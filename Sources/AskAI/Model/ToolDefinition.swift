internal import AemiJSON

/// A tool the model may call.
public struct ToolDefinition: Sendable, Equatable {
    public var name: String
    public var description: String
    /// The JSON Schema of the tool's input.
    public var inputSchema: JSONObject

    /// A tool with this name, description and schema.
    public init(name: String, description: String, inputSchema: JSONObject) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}
