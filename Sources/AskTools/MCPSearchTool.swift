internal import AemiJSON
public import AskAI
public import AskAgentCore
internal import Foundation

/// `mcp_search`: finds tools among the servers that have too many to list (ADR-0100).
struct MCPSearchTool: ArgumentTool {
    struct Arguments: Decodable, Sendable {
        let query: String
        let server: String?
    }

    /// The most tools one search shows.
    static let limit = 8

    let definition: ToolDefinition
    private let catalog: MCPCatalog

    /// The search over `catalog`, whose description names the servers it reaches.
    init(catalog: MCPCatalog) {
        self.catalog = catalog
        let reached = catalog.servers.map { "\($0.name) (\($0.tools) tools)" }.joined(separator: ", ")
        definition = ToolDefinition(
            name: "mcp_search",
            description: """
                Some MCP servers have too many tools to list here: \(reached). Find a tool among them by words from what you \
                want to do (a part of a tool's name counts most); each match shows what the tool does and the schema of its \
                arguments. Matches become directly callable on the next turn; mcp_call also works. An empty query lists names without promoting them.
                """
        ) {
            ToolProperty.string("query")
            ToolProperty.string("server").optional
        }
    }

    func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
        let candidates = catalog.candidates
        guard !candidates.isEmpty else { throw ToolFailure("No MCP server is connected with tools to search.") }
        let words = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if words.isEmpty {
            let pool = candidates.filter { arguments.server == nil || $0.server == arguments.server }
            return ToolOutput(MCPSearch.names(pool))
        }
        let matches = MCPSearch.rank(candidates, query: words, server: arguments.server, limit: Self.limit)
        guard !matches.isEmpty else {
            return ToolOutput(
                "No tool matches \"\(words)\". Search with other words, or with an empty query to list the names.")
        }
        catalog.promote(matches)
        let more =
            matches.count == Self.limit
            ? "\n\n(The best \(Self.limit); narrow the words or name a server for others.)" : ""
        return ToolOutput(
            MCPSearch.describe(matches, schemaBytes: MCPSearch.schemaBytes(forMatches: matches.count)) + more)
    }
}
