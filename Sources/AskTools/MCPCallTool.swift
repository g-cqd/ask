internal import AemiJSON
public import AskAI
public import AskAgentCore
internal import AskMCP

/// `mcp_call`: calls a tool found with `mcp_search` (ADR-0100). It runs outside ask's sandbox like every server's tool, so it refuses a
/// narrowed session.
struct MCPCallTool: Tool {
    let definition = ToolDefinition(
        name: "mcp_call",
        description: """
            Call a tool of an MCP server that mcp_search found: the server, the tool's name, and its arguments as an object that fits the \
            schema the search showed.
            """
    ) {
        ToolProperty.string("server")
        ToolProperty.string("tool")
        ToolProperty.schema("arguments", #"{"type":"object"}"#).optional
    }

    private let catalog: MCPCatalog

    /// The call over `catalog`.
    init(catalog: MCPCatalog) { self.catalog = catalog }

    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard context.sandbox == context.runSandbox else {
            return .error(MCPToolAdapter.narrowedRefusal(server: "that"))
        }
        guard let document = try? AemiJSON.parse(input.bytes, options: JSONParseOptions(recordsContainerSpans: true)),
            let server = document.root["server"].string, let tool = document.root["tool"].string
        else { return .error("Give the server and the tool, as mcp_search showed them.") }
        let given = document.root["arguments"]
        // Absent or null is no arguments; anything else that is not an object is a mistake to say, not to guess at.
        let isWrongKind = given.string != nil || given.bool != nil || given.double != nil || given.isArray
        guard !isWrongKind else { return .error("The arguments must be an object.") }
        let raw: JSONObject? =
            given.isObject ? (given.withRawJSONBytes { try? JSONObject(validating: Array($0)) } ?? nil) : nil
        let arguments = raw ?? .empty
        guard let connection = catalog.connection(server: server, tool: tool) else {
            let known = catalog.servers.map(\.name)
            let where_ =
                known.contains(server)
                ? "The server \(server) has no tool \(tool)" : "No searchable server is called \(server)"
            return .error("\(where_). Servers: \(known.joined(separator: ", ")). Use mcp_search to find the tools.")
        }
        return await MCPCalling.output(tool, arguments: arguments, on: connection, server: server)
    }
}
