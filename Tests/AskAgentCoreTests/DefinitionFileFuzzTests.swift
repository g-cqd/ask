import Testing

@testable import AskAgentCore

/// Reading cannot fail: any text at all, cut anywhere, gives a result, the same result twice, in bounded time.
@Suite("Reading a definition never fails, whatever it is given")
struct DefinitionFileFuzzTests {
    /// Every shape the owner's real files had, cut at every length: the half-written file is the one that finds the trap.
    private static let samples = [
        "---\nname: scout\ndescription: >\n  Read-only codebase exploration: locate files.\n  Reports findings; never edits.\nmodel: sonnet\n# fallback_models: claude-sonnet-5-5, haiku\neffort: low\ntools: Read, Grep, Bash(git diff:*)\nmaxTurns: 40\nhooks:\n  PreToolUse:\n    - matcher: \"Bash\"\n      hooks:\n        - type: command\n          command: 'python3 \"$HOME/x\" || exit 2'\n---\nBody.\n",
        "---\nname: x\ntools: [\"read\", \"search\", \"apple-docs/*\"]\nmodel: [\"Claude Opus 5.5\", \"GPT-6 Astra\"]\nallowed-tools:\n  - Read\n  - Glob\n---\n",
        "name = \"scout\"\nmodel = \"gpt-6-luna\"\n# fallback_models = [\"a\", \"b\"]\nenabled_tools = [\n  \"read\", # c\n  \"grep\"\n]\ndeveloper_instructions = '''\nYou are.\n'''\n[limits]\nturns = 3\n",
        "+++\nname = \"a\"\n+++\nbody",
        "\u{FEFF}---\r\nname: \"q\"\r\ndescription: 'it''s'\r\n---\r\n"
    ]

    private func summary(_ file: DefinitionFile) -> String {
        "\(file.format)|\(file.entries)|\(file.hints)|\(file.body)|\(file.diagnostics)"
    }

    @Test func `every cut of every real shape reads, twice the same, without a trap`() {
        for sample in Self.samples {
            let characters = Array(sample)
            for length in 0 ... characters.count {
                let text = String(characters[..<length])
                let yaml = DefinitionFile(parsing: text)
                #expect(summary(yaml) == summary(DefinitionFile(parsing: text)))
                let toml = DefinitionFile(parsing: text, isTOML: true)
                #expect(summary(toml) == summary(DefinitionFile(parsing: text, isTOML: true)))
                _ = ToolReference.parse(yaml.value("tools", "allowed-tools"))
                _ = ModelPreference(yaml)
            }
        }
    }

    @Test func `random text made of the characters that give a reader trouble reads`() {
        var generator = SeededGenerator(seed: 0x5EED)
        let alphabet = Array("--- +++ ::==[]{}\"'#|>-,\n\n\t  abcdefg\\\u{FEFF}\r日本")
        for _ in 0 ..< 3_000 {
            let text = String(
                (0 ..< Int.random(in: 0 ... 120, using: &generator))
                    .map { _ in alphabet.randomElement(using: &generator)! })
            let file = DefinitionFile(parsing: text)
            let again = DefinitionFile(parsing: text)
            #expect(summary(file) == summary(again), "\(text.debugDescription)")
            _ = ToolReference.parse(file.value("a", "b", "tools"))
            _ = ModelPreference(DefinitionFile(parsing: text, isTOML: true))
        }
    }

    @Test func `a huge head is read in bounded work`() {
        let many = (0 ..< 20_000).map { "k\($0): v" }.joined(separator: "\n")
        #expect(DefinitionFile(parsing: "---\n" + many + "\n---\n").entries.count == 20_000)
        #expect(DefinitionFile(parsing: "---\nkey: [" + String(repeating: "[", count: 50_000)).entries.count <= 1)
        #expect(DefinitionFile(parsing: "---\nkey: \"" + String(repeating: "a", count: 200_000)).entries.count <= 1)
    }
}
