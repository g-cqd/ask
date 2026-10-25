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
    private let connection: MCPConnection

    /// Wraps `tool` of `server`, offered to the model as `name`.
    init(server: String, tool: MCPTool, name: String, connection: MCPConnection) {
        self.server = server
        self.original = tool.name
        self.connection = connection
        let words = tool.description.isEmpty ? (tool.title ?? tool.name) : tool.description
        definition = ToolDefinition(
            name: name, description: "[MCP server \(server)] \(words)", inputSchema: tool.inputSchema)
    }

    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard context.sandbox == context.runSandbox else {
            return .error(
                "The sandbox was narrowed for this session, and the MCP server \(server) runs outside it, so its tools are off until the session is widened."
            )
        }
        do {
            let result = try await connection.callTool(original, arguments: input)
            let text = MCPResultText.of(result)
            return result.isError ? .error(text) : ToolOutput(text)
        } catch {
            return .error(MCPFailure.describe(error, server: server))
        }
    }
}
