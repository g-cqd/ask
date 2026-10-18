internal import AemiJSON

/// The UTF-8 bytes of one JSON object, validated once, so it can be spliced into every later request
/// without being parsed again.
public struct JSONObject: Sendable, Equatable {
    /// The bytes were not one JSON object.
    public struct Invalid: Error, Sendable, Equatable {}

    /// The object's bytes, exactly as given.
    public let bytes: [UInt8]

    /// `{}`.
    public static let empty = JSONObject(trusted: Array("{}".utf8))

    private init(trusted bytes: [UInt8]) { self.bytes = bytes }

    /// Validates `bytes` as one JSON object.
    /// - Throws: ``Invalid`` for anything else, including other JSON values.
    public init(validating bytes: [UInt8]) throws(Invalid) {
        guard (try? AemiJSON.parse(bytes))?.root.isObject == true else { throw Invalid() }
        self.bytes = bytes
    }
}

/// One block of a message sent to the model.
public enum RequestBlock: Sendable, Equatable {
    case text(String)
    case thinking(text: String, signature: String)
    case redactedThinking(data: String)
    case toolCall(id: String, name: String, input: JSONObject)
    case toolResult(id: String, content: String, isError: Bool)
}

/// A message in the conversation sent to the model.
public struct ModelMessage: Sendable, Equatable {
    public enum Role: Sendable, Equatable { case user, assistant }

    public var role: Role
    public var blocks: [RequestBlock]

    /// A message from `role`.
    public init(role: Role, blocks: [RequestBlock]) {
        self.role = role
        self.blocks = blocks
    }
}

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
