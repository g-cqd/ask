internal import AskAI
internal import AskAgentCore
internal import AskMCP

/// A call to a server's tool, made and read the same way whichever tool the model used to reach it.
enum MCPCalling {
    /// Calls `tool` on `connection` and returns what the model reads: the result's text, an error output for a tool that failed, and the
    /// words for a call that did not happen.
    static func output(
        _ tool: String, arguments: JSONObject, on connection: MCPConnection, server: String
    ) async -> ToolOutput {
        do {
            let result = try await connection.callTool(tool, arguments: arguments)
            let text = MCPResultText.of(result)
            return result.isError ? .error(text) : ToolOutput(text)
        } catch {
            return .error(MCPFailure.describe(error, server: server))
        }
    }
}
