internal import AskAI
internal import AskAgentCore
internal import AskMCP

/// A call to a server's tool, made and read the same way whichever tool the model used to reach it.
enum MCPCalling {
    /// Calls `tool` on `connection`, telling `context` of the server's progress, and returns what the model reads: the result's text and its pictures made fit to send, an error output for a tool that failed, and the
    /// words for a call that did not happen.
    static func output(
        _ tool: String,
        arguments: JSONObject,
        on connection: MCPConnection,
        server: String,
        context: ToolContext
    ) async -> ToolOutput {
        // Progress is asked for only when someone shows it, so a quiet run sends the server no token.
        let onProgress: (@Sendable (MCPProgress) -> Void)? =
            context.reportsProgress ? { @Sendable report in context.reportProgress(MCPProgressLine.of(report)) } : nil
        let allowance = ImageReader.Allowance(context.imageLimits)
        do {
            let result = try await connection.callTool(tool, arguments: arguments, onProgress: onProgress)
            let pictures = MCPResultImages(result, allowance: allowance)
            let text = MCPResultText.of(result, replacing: pictures.lines)
            guard !result.isError else { return .error(text) }
            var output = ToolOutput(text)
            output.images = pictures.parts
            return output
        } catch {
            return .error(MCPFailure.describe(error, server: server))
        }
    }
}
