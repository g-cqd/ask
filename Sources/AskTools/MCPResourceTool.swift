internal import AemiJSON
public import AskAI
public import AskAgentCore
internal import AskMCP

/// `server_resource`: lists or reads what a connected server offers as resources (roadmap 0067), offered only while one does. It runs outside
/// ask's sandbox like every server's tool, so it refuses a narrowed session. Not `mcp_…`: see ``MCPCallTool``.
struct MCPResourceTool: Tool {
    let definition = ToolDefinition(
        name: "server_resource",
        description: """
            Read what an MCP server offers as resources. The server alone lists its resources and URI templates; with a uri, from the list \
            or a template filled in, reads it.
            """
    ) {
        ToolProperty.string("server")
        ToolProperty.string("uri").optional
    }

    private let shelf: MCPResourceShelf

    init(shelf: MCPResourceShelf) { self.shelf = shelf }

    func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
        guard context.sandbox == context.runSandbox else {
            return .error(MCPToolAdapter.narrowedRefusal(server: "that"))
        }
        let root = (try? AemiJSON.parse(input.bytes))?.root
        guard let server = root?["server"].string else { return .error("Give the server, and a uri to read one.") }
        guard let connection = shelf.connection(server) else {
            return .error(
                "No connected server called \(server) has resources. Servers with resources: \(shelf.names.joined(separator: ", "))."
            )
        }
        do {
            if let uri = root?["uri"].string, !uri.isEmpty {
                return Self.output(try await connection.readResource(uri), allowance: .init(context.imageLimits))
            }
            let resources = try await connection.listResources()
            // A server may list resources and have no templates; a refused templates listing is none.
            let templates = (try? await connection.listResourceTemplates()) ?? []
            return ToolOutput(MCPResourceListing.text(server: server, resources: resources, templates: templates))
        } catch {
            return .error(MCPFailure.describe(error, server: server))
        }
    }

    /// What a read gives the model: as a tool's result would, the text whole, pictures shown, and other bytes named.
    static func output(_ parts: [MCPResourceContents], allowance: ImageReader.Allowance) -> ToolOutput {
        let content = parts.map { part -> MCPContent in
            switch part.body {
                case .text(let text): .text(text)
                case .blob(let base64) where part.mimeType?.hasPrefix("image/") == true:
                    .image(mimeType: part.mimeType ?? "", base64: base64)
                case .blob: .resource(uri: part.uri, mimeType: part.mimeType, text: nil)
            }
        }
        let result = MCPToolResult(content: content, structuredContent: nil, isError: false)
        let pictures = MCPResultImages(result, allowance: allowance)
        var output = ToolOutput(MCPResultText.of(result, replacing: pictures.lines))
        output.images = pictures.parts
        return output
    }
}
