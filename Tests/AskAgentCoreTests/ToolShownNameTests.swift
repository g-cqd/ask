import AskAI
import Testing

@testable import AskAgentCore

/// The name a tool's block is headed with (note n25): readable, never the wire name a provider needs.
@Suite("A tool is shown by a name a person reads")
struct ToolShownNameTests {
    private func input(_ json: String) throws -> JSONObject { try JSONObject(validating: Array(json.utf8)) }

    @Test func `a server's tool reads as server and tool`() {
        #expect(ToolSummary.shownName("mcp__apple-docs__search_docs") == "apple-docs/search_docs")
        #expect(ToolSummary.shownName("mcp__swift-search__find_usages") == "swift-search/find_usages")
    }

    @Test func `a dispatched call reads as the server's tool it calls`() throws {
        let call = try input(#"{"server":"xcode","tool":"BuildProject","arguments":{}}"#)
        #expect(ToolSummary.shownName("dispatch_call", input: call) == "xcode/BuildProject")
        #expect(
            ToolSummary.shownName("dispatch_call", input: try input("{}")) == "dispatch_call",
            "without its target, its own name"
        )
    }

    @Test func `ask's own tools keep their names, and bash is the shell`() {
        #expect(ToolSummary.shownName("bash") == "shell")
        for name in ["read", "edit", "write", "skill", "tasks", "notes", "job"] {
            #expect(ToolSummary.shownName(name) == name)
        }
    }

    @Test func `a name that only looks like a server's is left whole`() {
        for name in ["mcp__", "mcp__server", "mcp____tool", "mcp__server__"] {
            #expect(ToolSummary.shownName(name) == name)
        }
    }
}
