// @dl:accept -- a server's tools share their imports, holder and sandbox refusal; each says its own definition and work (server_resource)
internal import AemiJSON
public import AskAI
public import AskAgentCore
internal import AskMCP

/// `dispatch_call`: calls a tool found with `search_catalog` (ADR-0100). It runs where its server does, outside the session's narrowing, so it refuses a
/// narrowed session. Not `mcp_call`: Anthropic refuses a Claude subscription request that offers a tool called `mcp_call` or `mcp_search`,
/// with an "out of extra usage" message (roadmap 0144); these names were checked live to pass.
// @dl:accept -- a tool declares its arguments and what each says through one builder: the lists are data
struct MCPCallTool: Tool {
    let definition = ToolDefinition(
        name: "dispatch_call",
        description: """
            Call a tool of an MCP server that search_catalog found.
            """
    ) {
        ToolProperty.string("server").described("The server, as the search named it.")
        ToolProperty.string("tool").described("The tool's name on that server.")
        // @dl:accept -- like server_resource, it holds what it reaches servers through and refuses a narrowed session first
        ToolProperty.schema("arguments", #"{"type":"object"}"#)
            .described("The tool's arguments, fitting the schema the search showed.").optional
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
        else { return .error("Give the server and the tool, as search_catalog showed them.") }
        let given = document.root["arguments"]
        // Absent or null is no arguments; anything else that is not an object is a mistake to say, not to guess at.
        let isWrongKind = given.string != nil || given.bool != nil || given.double != nil || given.isArray
        guard !isWrongKind else { return .error("The arguments must be an object.") }
        let raw: JSONObject? =
            given.isObject ? (given.withRawJSONBytes { try? JSONObject(validating: Array($0)) } ?? nil) : nil
        let arguments = raw ?? .empty
        guard let found = catalog.find(server: server, tool: tool) else {
            let known = catalog.servers.map(\.name)
            let where_ =
                known.contains(server)
                ? "The server \(server) has no tool \(tool)" : "No searchable server is called \(server)"
            return .error("\(where_). Servers: \(known.joined(separator: ", ")). Use search_catalog to find the tools.")
        }
        if found.tool.annotations.needsApproval, let approve = context.destructiveApprover {
            guard await approve(DestructiveToolCall(server: server, tool: tool, input: arguments)) else {
                return .error(MCPToolAdapter.refused(server: server, tool: tool))
            }
        }
        return await MCPCalling.output(
            tool,
            arguments: arguments,
            on: found.connection,
            server: server,
            context: context
        )
    }
}
