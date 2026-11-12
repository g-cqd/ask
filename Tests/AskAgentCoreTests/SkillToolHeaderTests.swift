import AskAI
import Testing

@testable import AskAgentCore

/// The skill tool's header (roadmap 0078): the skill it loads, or the words it searches for, or that it browses, with the sources
/// it narrows to; never its raw JSON. Only the skill tool is read this way: another tool with a `name` keeps its input.
@Suite("The skill tool's header says what it loads or looks for")
struct SkillToolHeaderTests {
    private func header(_ json: String, tool: String? = "skill") throws -> String {
        ToolSummary.header(for: try JSONObject(validating: Array(json.utf8)), tool: tool)
    }

    @Test func `loading a skill shows its name`() throws {
        #expect(try header(#"{"name":"pdf"}"#) == "pdf")
        #expect(try header(#"{"name":"pdf","from":"claude"}"#) == "pdf · from claude")
    }

    @Test func `a search shows its words, and an empty one browses`() throws {
        #expect(try header(#"{"query":"swift testing"}"#) == "search · swift testing")
        #expect(try header(#"{"query":""}"#) == "browse")
        #expect(try header("{}") == "browse")
        #expect(try header(#"{"query":"","from":["project","codex"]}"#) == "browse · from project, codex")
    }

    @Test func `a name wins over a query, as the tool reads them`() throws {
        #expect(try header(#"{"name":"pdf","query":"ignored"}"#) == "pdf")
    }

    @Test func `another tool with the same fields keeps its input`() throws {
        #expect(try header(#"{"name":"pdf"}"#, tool: "mcp__x__get") == "name pdf")
        #expect(try header(#"{"name":"pdf"}"#, tool: nil) == "name pdf")
    }
}
