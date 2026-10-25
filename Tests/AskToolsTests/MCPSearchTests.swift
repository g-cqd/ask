import AskAI
import AskMCP
import Testing

@testable import AskTools

/// Finding a tool among a large server's (ADR-0100): by the words of its name and description, the best first, bounded, and shown with the
/// schema the model needs to call it.
@Suite("A search over a large server's tools ranks by name and description, and shows what a call needs")
struct MCPSearchTests {
    private static func tool(_ name: String, _ description: String, schema: String = #"{"type":"object"}"#) -> MCPTool {
        MCPTool(
            name: name, title: nil, description: description,
            inputSchema: try! JSONObject(validating: Array(schema.utf8)), annotations: MCPToolAnnotations(),
            hasOutputSchema: false)
    }

    private let catalog: [MCPSearch.Candidate] = [
        .init(server: "rea", tool: tool("list_functions", "Lists the functions of a binary.")),
        .init(server: "rea", tool: tool("decompile_function", "Decompiles one function to pseudo code.")),
        .init(server: "rea", tool: tool("read_memory", "Reads bytes from the process memory of a binary.")),
        .init(server: "docs", tool: tool("search_docs", "Searches the documentation for a function or a type."))
    ]

    private func names(_ query: String, server: String? = nil, limit: Int = 10) -> [String] {
        MCPSearch.rank(catalog, query: query, server: server, limit: limit).map { "\($0.server)/\($0.tool.name)" }
    }

    @Test func `a word in a tool's name beats the same word in its description`() {
        #expect(names("decompile").first == "rea/decompile_function")
        #expect(names("memory").first == "rea/read_memory")
    }

    @Test func `one word in a name outweighs two words in a description`() {
        let pool: [MCPSearch.Candidate] = [
            .init(server: "s", tool: Self.tool("y", "Dumps the memory dump.")),
            .init(server: "s", tool: Self.tool("memory_x", "Does x."))
        ]
        #expect(MCPSearch.rank(pool, query: "memory dump", server: nil, limit: 2).map(\.tool.name) == ["memory_x", "y"])
    }

    @Test func `every word counts, so the tool that has most of them is first`() {
        #expect(names("decompile function").first == "rea/decompile_function")
        #expect(names("list functions binary").first == "rea/list_functions")
    }

    @Test func `a tool with none of the words is not a match`() {
        #expect(names("zebra").isEmpty)
        #expect(!names("memory").contains("docs/search_docs"))
    }

    @Test func `case and punctuation do not matter`() {
        #expect(names("DECOMPILE, Function!").first == "rea/decompile_function")
        #expect(names("read-memory").first == "rea/read_memory")
    }

    @Test func `a server can be asked for by name`() {
        #expect(names("function", server: "docs") == ["docs/search_docs"])
        #expect(names("function", server: "nobody").isEmpty)
    }

    @Test func `the limit bounds the answer and ties keep the catalog's order`() {
        #expect(names("function", limit: 2).count == 2)
        #expect(names("binary") == ["rea/list_functions", "rea/read_memory"])
    }

    @Test func `no words lists everything, in order, up to the limit`() {
        #expect(names("").count == 4 && names("  ").first == "rea/list_functions")
        #expect(names("", limit: 3).count == 3)
    }

    @Test func `the answer gives the server, the tool, what it does and the schema of its arguments`() {
        let shown = MCPSearch.describe(
            [
                .init(
                    server: "rea",
                    tool: Self.tool("read_memory", "Reads bytes.", schema: #"{"type":"object","required":["address"]}"#)
                )
            ],
            schemaBytes: 1000)
        #expect(shown.contains("rea / read_memory") && shown.contains("Reads bytes."))
        #expect(shown.contains(#"{"type":"object","required":["address"]}"#))
    }

    @Test func `a schema too large to show is cut, and the cut is said`() {
        let big = #"{"type":"object","description":"\#(String(repeating: "x", count: 500))"}"#
        let shown = MCPSearch.describe([.init(server: "s", tool: Self.tool("t", "d", schema: big))], schemaBytes: 100)
        #expect(shown.contains("schema cut at 100 of") && !shown.contains(String(repeating: "x", count: 200)))
    }

    @Test func `the schema budget is shared out, and one tool gets most of its schema`() {
        #expect(MCPSearch.schemaBytes(forMatches: 1) == 12_000 && MCPSearch.schemaBytes(forMatches: 2) == 6000)
        #expect(MCPSearch.schemaBytes(forMatches: 4) == 3000 && MCPSearch.schemaBytes(forMatches: 8) == 3000)
        #expect(MCPSearch.schemaBytes(forMatches: 0) == 12_000, "no matches is not a division by zero")
    }

    @Test func `a description is cut to a few hundred characters`() {
        let shown = MCPSearch.describe(
            [.init(server: "s", tool: Self.tool("t", String(repeating: "w", count: 2000)))], schemaBytes: 100)
        #expect(shown.count < 900 && shown.contains("…"))
    }

    @Test func `browsing lists names only, compactly`() {
        let listing = MCPSearch.names(catalog)
        #expect(listing == "rea: list_functions, decompile_function, read_memory\ndocs: search_docs")
    }
}
