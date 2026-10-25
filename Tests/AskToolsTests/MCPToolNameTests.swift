import Testing

@testable import AskTools

/// A server's tool becomes ask's `mcp__<server>__<tool>` (ADR-0099, and ADR-0092 keeps these names whole): within what providers accept
/// for a tool name, and the same for the same tool every time so a session resumed later calls what it called before.
@Suite("A server's tool gets a name a provider accepts and the same one every time")
struct MCPToolNameTests {
    @Test func `a plain name is the server and the tool, joined`() {
        #expect(MCPToolName.make(server: "rea", tool: "search_docs") == "mcp__rea__search_docs")
        #expect(MCPToolName.make(server: "x", tool: "get-sum") == "mcp__x__get-sum")
    }

    @Test func `what a provider does not accept in a name becomes an underscore, and the name is told apart by a hash`()
    {
        let name = MCPToolName.make(server: "s", tool: "a.b c")
        #expect(name.hasPrefix("mcp__s__a_b_c_") && MCPToolName.isAcceptable(name))
        #expect(MCPToolName.make(server: "s", tool: "a.b c") == name, "the same every time")
        #expect(
            MCPToolName.make(server: "s", tool: "a b.c") != name, "two tools that sanitise alike are still two names")
    }

    @Test func `a name past sixty-four characters is cut and hashed, and stays within the limit`() {
        let long = String(repeating: "t", count: 100)
        let name = MCPToolName.make(server: "server", tool: long)
        #expect(name.utf8.count <= 64 && name.hasPrefix("mcp__server__ttt") && MCPToolName.isAcceptable(name))
        #expect(name != MCPToolName.make(server: "server", tool: long + "x"))
    }

    @Test func `a name that is exactly sixty-four characters is left alone`() {
        let tool = String(repeating: "t", count: 64 - "mcp__s__".count)
        #expect(MCPToolName.make(server: "s", tool: tool) == "mcp__s__" + tool)
    }

    @Test func `non-ASCII letters are not accepted, and are told apart`() {
        #expect(MCPToolName.make(server: "s", tool: "é") != MCPToolName.make(server: "s", tool: "è"))
        #expect(MCPToolName.isAcceptable(MCPToolName.make(server: "s", tool: "日本語")))
    }

    @Test func `a name belongs to an mcp server if it starts with the prefix`() {
        #expect(MCPToolName.isMCP("mcp__a__b") && !MCPToolName.isMCP("bash") && !MCPToolName.isMCP("mcp_a"))
    }
}
