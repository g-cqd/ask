import Testing

@testable import AskAgentCore

/// Tool lists are read however they were written, and a name ask does not know is kept, not refused.
@Suite("A tool list is read as the words it holds, and nothing in it can fail")
struct ToolReferenceTests {
    private func tokens(_ text: String) -> [String] {
        ToolReference.parse(DefinitionFile(parsing: "---\ntools: \(text)\n---\n").value("tools")).map(\.token)
    }

    @Test func `a comma string, a space string and a flow list give the same words`() {
        #expect(tokens("Read, Grep, Glob") == ["Read", "Grep", "Glob"])
        #expect(tokens("Read Grep Glob") == ["Read", "Grep", "Glob"])
        #expect(tokens("[\"read\", 'search', web]") == ["read", "search", "web"])
    }

    @Test func `a block list in another harness's vocabulary is read, and mapped where ask has the tool`() {
        let file = DefinitionFile(
            parsing: "---\ntools:\n  - send_message\n  - view_file\n  - grep_search\n  - run_command\n---\n")
        let references = ToolReference.parse(file.value("tools"))
        #expect(references.map(\.token) == ["send_message", "view_file", "grep_search", "run_command"])
        #expect(references.map(\.ask) == [nil, "read", "grep", "bash"])
    }

    @Test func `parentheses keep their spaces, and the part inside is a qualifier`() {
        let references = ToolReference.parse(.text("Bash(git diff:*), Read, Bash(rm -rf /)"))
        #expect(references.map(\.token) == ["Bash(git diff:*)", "Read", "Bash(rm -rf /)"])
        #expect(references.map(\.ask) == ["bash", "read", "bash"])
        #expect(references.map(\.qualifier) == ["git diff:*", nil, "rm -rf /"])
    }

    @Test func `unknown names, wildcards and namespaced names are kept and map to nothing`() {
        let references = ToolReference.parse(.text("LSP, mcp__apple-docs, apple-docs/*, WebFetch, read"))
        #expect(references.map(\.token) == ["LSP", "mcp__apple-docs", "apple-docs/*", "WebFetch", "read"])
        #expect(references.map(\.ask) == [nil, nil, nil, nil, "read"])
    }

    @Test func `case and punctuation do not matter, and a repeat is one`() {
        let references = ToolReference.parse(.list([.text("READ_FILE"), .text("readFile")]))
        #expect(
            references.map(\.ask) == ["read", "read"],
            "the two spellings that differ are kept, each mapped; the exact repeat of one is not")
        #expect(ToolReference.parse(.text("Read, Read, Read")).count == 1)
    }

    @Test func `bullets, quotes, backticks and stray commas are stripped`() {
        #expect(ToolReference.parse(.text("- \"Read\",\n- `Grep`,\n* Bash;")).map(\.token) == ["Read", "Grep", "Bash"])
    }

    @Test func `nothing, an empty list and an empty string give no tools`() {
        #expect(ToolReference.parse(nil).isEmpty)
        #expect(ToolReference.parse(.list([])).isEmpty)
        #expect(ToolReference.parse(.text("  ,  ; ")).isEmpty)
    }

    @Test func `ask's own tool names map to themselves`() {
        for name in ["read", "write", "edit", "bash", "wait", "job_input", "job_stop", "narrow_sandbox"] {
            #expect(ToolAliasTable.standard.lookup(name) == name, "\(name)")
        }
    }

    @Test func `every spelling seen in the owner's harness files is mapped or deliberately not`() {
        let mapped = [
            "write_to_file": "write", "replace_file_content": "edit", "multi_replace_file_content": "edit",
            "invoke_subagent": "agent"
        ]
        for (spelling, tool) in mapped { #expect(ToolAliasTable.standard.lookup(spelling) == tool, "\(spelling)") }
        for spelling in [
            "LSP", "WebFetch", "WebSearch", "web", "TodoWrite", "send_message", "call_mcp_tool", "read_url_content"
        ] {
            #expect(ToolAliasTable.standard.lookup(spelling) == nil, "ask has no such tool: \(spelling)")
        }
    }

    @Test func `a table is data: another row, another harness`() {
        let table = ToolAliasTable(["read": ["open_the_file"]])
        #expect(table.lookup("Open The File") == "read" && table.lookup("view_file") == nil)
    }
}
