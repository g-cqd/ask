internal import AemiJSON
public import AskAI
public import AskAgentCore
internal import AskMCP

/// One tool of an MCP server, as ask's own kind of tool (ADR-0099). It runs outside ask's sandbox, as the server does, so it refuses a
/// session that has been narrowed: that narrowing is a promise the server could not keep.
struct MCPToolAdapter: Tool {
    let definition: ToolDefinition
    private let server: String
    private let original: String
    private let destructive: Bool
    private let connection: MCPConnection

    /// Wraps `tool` of `server`, offered to the model as `name`.
    init(server: String, tool: MCPTool, name: String, connection: MCPConnection) {
        self.server = server
        self.original = tool.name
        self.destructive = tool.annotations.destructive == true
        self.connection = connection
        let words = tool.description.isEmpty ? (tool.title ?? tool.name) : tool.description
        definition = ToolDefinition(
            name: name, description: "[MCP server \(server)] \(words)", inputSchema: tool.inputSchema)
    }

    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard context.sandbox == context.runSandbox else { return .error(Self.narrowedRefusal(server: server)) }
        if destructive, let approve = context.destructiveApprover {
            guard await approve(DestructiveToolCall(server: server, tool: original, input: input)) else {
                return .error(Self.refused(server: server, tool: original))
            }
        }
        return await MCPCalling.output(original, arguments: input, on: connection, server: server)
    }

    /// What the model is told when the user did not allow a call the server marks destructive (ADR-0111).
    static func refused(server: String, tool: String) -> String {
        "The user did not allow \(tool) on the MCP server \(server); the server marks it destructive. Ask the user, or do without it."
    }

    /// What the model is told when the sandbox was narrowed.
    static func narrowedRefusal(server: String) -> String {
        "The sandbox was narrowed for this session, and the MCP server \(server) runs outside it, so its tools are off until the session is widened."
    }
}
