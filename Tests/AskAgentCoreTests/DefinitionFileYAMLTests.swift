import Testing

@testable import AskAgentCore

/// A definition file is read for what it holds, in every shape real harness directories have.
@Suite("A definition's head is read in whatever shape it was written")
struct DefinitionFileYAMLTests {
    private func read(_ text: String) -> DefinitionFile { DefinitionFile(parsing: text) }

    @Test func `a plain head gives its fields, and the body is what follows it`() {
        let file = read("---\nname: scout\ndescription: Finds things.\n---\n# Body\nText\n")
        #expect(file.format == .yaml)
        #expect(file.text("name") == "scout" && file.text("description") == "Finds things.")
        #expect(file.body == "# Body\nText\n")
        #expect(file.diagnostics.isEmpty)
    }

    @Test func `folded and literal block scalars, with any chomping, give their text`() {
        let folded = read(
            "---\ndescription: >\n  Read-only codebase\n  exploration: locate files.\n\n  Second paragraph.\nname: x\n---\n"
        )
        #expect(folded.text("description") == "Read-only codebase exploration: locate files.\nSecond paragraph.")
        #expect(folded.text("name") == "x")
        #expect(read("---\ndescription: >-\n  one\n  two\n---\n").text("description") == "one two")
        #expect(read("---\ndescription: |\n  line one\n  line two\n---\n").text("description") == "line one\nline two")
        #expect(read("---\nwhen_to_use: |-\n    kept\n      indent\n---\n").text("when_to_use") == "kept\n  indent")
    }

    @Test func `blank lines after a block scalar are not part of it`() {
        let file = read("---\ndescription: |\n  one\n  two\n\n\nname: n\n---\n")
        #expect(file.text("description") == "one\ntwo")
        #expect(file.value("description")?.scalar == "one\ntwo", "not even a trailing line break")
    }

    @Test func `quoted values keep their colons, hashes and escapes, and a quoted name loses its quotes`() {
        let file = read(
            "---\nname: \"openai-docs\"\ndescription: 'It''s: a # not a comment'\nargument-hint: \"[a] \\\"b\\\" \\u00e9\"\n---\n"
        )
        #expect(file.text("name") == "openai-docs")
        #expect(file.text("description") == "It's: a # not a comment")
        #expect(file.text("argument-hint") == "[a] \"b\" é")
    }

    @Test func `a plain value continues over more-indented lines, and a comment after it is not part of it`() {
        let file = read("---\ndescription: one\n  two\n  three # trailing\nname: n # also trailing\n---\n")
        #expect(file.text("description") == "one two three")
        #expect(file.text("name") == "n")
    }

    @Test func `lists are read as flow lists, block lists, indented or not, and comma strings`() {
        let file = read(
            "---\ntools: Read, Grep, Glob\nflow: [\"read\", 'search', web]\nblock:\n  - one\n  - two\nflush:\n- a\n- b\nafter: x\n---\n"
        )
        #expect(file.value("tools")?.scalar == "Read, Grep, Glob")
        #expect(file.value("flow") == .list([.text("read"), .text("search"), .text("web")]))
        #expect(file.value("block") == .list([.text("one"), .text("two")]))
        #expect(file.value("flush") == .list([.text("a"), .text("b")]))
        #expect(file.text("after") == "x")
    }

    @Test func `a flow list may run over lines, and text that only looks like one is text`() {
        let file = read(
            "---\nmodel: [\"Claude Opus 5.5\",\n  \"GPT-6 Astra\"]\ndescription: [WIP] fix the thing\n---\n")
        #expect(file.value("model") == .list([.text("Claude Opus 5.5"), .text("GPT-6 Astra")]))
        #expect(file.text("description") == "[WIP] fix the thing")
    }

    @Test func `nested maps and lists of maps are kept, to any depth, without trouble`() {
        let text = """
            ---
            name: scout
            metadata:
              author: me
              version: "1"
            hooks:
              PreToolUse:
                - matcher: "Bash"
                  hooks:
                    - type: command
                      command: 'python3 "$HOME/x.py" || exit 2'
            maxTurns: 40
            ---
            """
        let file = read(text)
        #expect(
            file.value("metadata")
                == .map([
                    DefinitionEntry(key: "author", value: .text("me")),
                    DefinitionEntry(key: "version", value: .text("1"))
                ]))
        #expect(file.text("maxTurns") == "40")
        #expect(file.value("hooks") != nil && file.diagnostics.isEmpty)
        #expect(file.value("hooks")?.scalars.contains("Bash") == true)
    }

    @Test func `keys are compared by meaning, so any spelling of allowed-tools is the same key`() {
        for spelling in ["allowed-tools", "allowed_tools", "allowedTools", "Allowed Tools", "ALLOWED-TOOLS"] {
            let file = read("---\n\(spelling): Read\n---\n")
            #expect(file.text("allowed-tools") == "Read", "\(spelling)")
        }
    }

    @Test func `comments of the form key: value are kept as hints, and other comments are not`() {
        let file = read(
            "---\nmodel: opus\n# fallback_models: claude-opus-5-5, sonnet\n# just a remark about the file\neffort: low\n---\n"
        )
        #expect(file.hint("fallback_models")?.scalar == "claude-opus-5-5, sonnet")
        #expect(file.hints.count == 1)
        #expect(read("---\nmodel: x\n# tier_models: [a, b] (effort: low)\n---\n").hint("tiermodels") != nil)
    }

    @Test func `a key written twice keeps the last value and says so`() {
        let file = read("---\nname: first\nname: second\n---\n")
        #expect(file.text("name") == "second")
        #expect(file.entries.count == 1 && file.diagnostics.count == 1)
    }

    @Test
    func `a byte-order mark, carriage returns, blank lines first and trailing spaces on a fence are all tolerated`() {
        let file = read("\u{FEFF}\r\n\r\n---  \r\nname: a\r\ndescription: b\r\n---\t\r\nbody\r\n")
        #expect(file.text("name") == "a" && file.text("description") == "b")
        #expect(file.body == "body\n")
    }

    @Test func `no head at all is a body and nothing else`() {
        let file = read("# A skill\n\nJust text.\n")
        #expect(file.format == .none && file.entries.isEmpty && file.body == "# A skill\n\nJust text.\n")
    }

    @Test func `a head that never closes is read up to its first blank line, and says so`() {
        let file = read("---\nname: a\ndescription: b\n\nThis is the body, not the head.\n")
        #expect(file.text("name") == "a" && file.text("description") == "b")
        #expect(file.body.contains("This is the body"))
        #expect(!file.diagnostics.isEmpty)
    }

    @Test func `lines that are not key: value are skipped with a note, and the rest still reads`() {
        let file = read("---\nname: a\nthis line is nonsense\ndescription: b\n---\n")
        #expect(file.text("name") == "a" && file.text("description") == "b")
        #expect(file.diagnostics.count == 1)
    }

    @Test func `tabs for indentation read as indentation`() {
        let file = read("---\ndescription: >\n\tfolded with a tab\nname: n\n---\n")
        #expect(file.text("description") == "folded with a tab" && file.text("name") == "n")
    }
}
