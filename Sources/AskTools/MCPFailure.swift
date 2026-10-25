internal import AskMCP

/// A server's failures in words for the model and the person.
enum MCPFailure {
    /// `error`, said as what happened to `server`.
    static func describe(_ error: any Error, server: String) -> String {
        guard let error = error as? MCPError else { return "The MCP server \(server) failed: \(error)" }
        switch error {
            case .rpc(_, let message): return "The MCP server \(server) refused: \(message)"
            case .timedOut(let method): return "The MCP server \(server) did not answer \(method) in time."
            case .cancelled: return "The call to the MCP server \(server) was cancelled."
            case .disconnected: return "The MCP server \(server) went away."
            case .unsupportedVersion(let version):
                return "The MCP server \(server) speaks protocol version \(version), which ask does not."
            case .refusedEndpoint(let reason): return "ask will not connect to the MCP server \(server): \(reason)."
            case .malformedResponse(let what): return "The MCP server \(server) sent something unreadable: \(what)."
            case .notStarted, .alreadyStarted: return "The MCP server \(server) is not in a state to be called."
            case .tooManyPages: return "The MCP server \(server) never finished listing its tools."
        }
    }
}
