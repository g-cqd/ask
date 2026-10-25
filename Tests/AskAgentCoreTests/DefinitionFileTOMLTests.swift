import Testing

@testable import AskAgentCore

/// Codex's and Vibe's agent files are whole TOML files, and a TOML head can sit in fences.
@Suite("A TOML definition is read for its key = value lines")
struct DefinitionFileTOMLTests {
    private static let codex = """
        name = "scout"
        description = "Read-only exploration: where \\"it\\" is."
        model = "gpt-6-luna"
        # fallback_models = ["gpt-5.6-luna", "gpt-6.1-sol", "gpt-5.5"]
        model_reasoning_effort = "low"
        # Codex 0.149 and later ignore sandbox_mode here.
        sandbox_mode = "read-only"
        enabled_tools = [
          "read_file", # a comment inside
          "grep",
          "bash"
        ]
        max_turns = 40
        developer_instructions = '''
        You are the scout.
        Never edit.
        '''
        """

    @Test func `strings in every form, arrays over lines, and numbers as written`() {
        let file = DefinitionFile(parsing: Self.codex, isTOML: true)
        #expect(file.format == .toml)
        #expect(file.text("name") == "scout" && file.text("model") == "gpt-6-luna")
        #expect(file.text("description") == "Read-only exploration: where \"it\" is.")
        #expect(file.value("enabled_tools") == .list([.text("read_file"), .text("grep"), .text("bash")]))
        #expect(file.text("max_turns") == "40")
        #expect(file.text("developer_instructions") == "You are the scout.\nNever edit.")
        #expect(file.diagnostics.isEmpty)
    }

    @Test func `a comment that holds a setting in TOML's own form is a hint`() {
        let file = DefinitionFile(parsing: Self.codex, isTOML: true)
        #expect(file.hint("fallback_models") == .list([.text("gpt-5.6-luna"), .text("gpt-6.1-sol"), .text("gpt-5.5")]))
        #expect(file.hints.count == 1)
    }

    @Test func `tables become a prefix on the keys under them`() {
        let file = DefinitionFile(parsing: "name = \"a\"\n[limits]\nturns = 3\n", isTOML: true)
        #expect(file.text("limits.turns") == "3")
    }

    @Test func `a TOML head in plus-fences has a body after it`() {
        let file = DefinitionFile(parsing: "+++\nname = \"a\"\ndescription = 'b'\n+++\nThe body.\n")
        #expect(file.format == .toml && file.text("name") == "a" && file.text("description") == "b")
        #expect(file.body == "The body.\n")
    }

    @Test func `a line that is not an assignment is skipped, and a repeated key keeps the last`() {
        let file = DefinitionFile(parsing: "name = \"a\"\nnonsense here\nname = \"b\"\n", isTOML: true)
        #expect(file.text("name") == "b" && file.diagnostics.count == 2)
    }

    @Test func `an array that never closes does not eat the file`() {
        let lines = (0 ..< 1_000).map { "line\($0) = \"x\"" }.joined(separator: "\n")
        let file = DefinitionFile(parsing: "a = [\"x\"\n" + lines, isTOML: true)
        #expect(file.entries.count >= 500)
    }
}
