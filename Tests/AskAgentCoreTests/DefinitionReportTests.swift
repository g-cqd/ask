import Testing

@testable import AskAgentCore

@Suite("The inspection report says how a file was read")
struct DefinitionReportTests {
    @Test func `a Markdown agent shows its fields, its tools as mapped, its models and its notes`() {
        let text =
            "---\nname: scout\nmodel: sonnet\n# fallback_models: haiku\ntools: Read, LSP, Bash\nname: again\n---\nBody"
        let lines = DefinitionReport(path: "/x/scout.md", text: text).lines
        #expect(lines[0] == "/x/scout.md: yaml head, 3 fields, 1 comment hints, body 4 characters")
        #expect(lines.contains("    tools: Read→read, LSP→?, Bash→bash"))
        #expect(lines.contains("    models: sonnet > haiku (then the parent's)") == false)
        #expect(lines.contains("    models: sonnet > haiku"))
        #expect(lines.contains { $0.hasPrefix("    note: the key") })
    }

    @Test func `a toml file is read as toml by its name, and a file with no head says so`() {
        #expect(DefinitionReport(path: "/x/a.TOML", text: "name = \"a\"\n").lines[0].contains("toml, 1 fields"))
        #expect(DefinitionReport(path: "/x/a.md", text: "just text").lines[0].contains("no head, 0 fields"))
    }
}
