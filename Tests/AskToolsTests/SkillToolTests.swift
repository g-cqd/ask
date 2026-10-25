import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The `skill` tool serves skills discovery already found, by name, and cannot be made to read anywhere else.
@Suite("The skill tool loads a skill by name and cannot name a place")
struct SkillToolTests {
    private let sources = [
        SkillSource(id: "agents", userRoots: [".agents/skills"], projectRoots: [], bundledRoots: []),
        SkillSource(id: "claude", userRoots: [".claude/skills"], projectRoots: [], bundledRoots: []),
        SkillSource(id: "agy", userRoots: [], projectRoots: [], bundledRoots: [".gemini/builtin/skills"])
    ]
    private let home: String
    private let context: ToolContext

    init() throws {
        home = FileManager.default.temporaryDirectory.appending(path: "ask-skilltool-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        context = ToolContext(workingDirectory: home)
    }

    private func write(_ path: String, _ text: String) throws {
        let full = home + "/" + path
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: full, atomically: true, encoding: .utf8)
    }

    private func tool() -> SkillTool {
        let known = sources.map(\.id)
        let catalog = SkillDiscovery.discover(
            workingDirectory: home, home: home, sources: sources,
            selection: SkillSelection(tokens: ["user", "bundled"], knownSources: known))
        return SkillTool(catalog: catalog, knownSources: known)
    }

    private func run(_ json: String) async throws -> ToolOutput {
        await tool().run(try JSONObject(validating: Array(json.utf8)), in: context)
    }

    @Test func `a skill's body comes back with where it lives, and its head does not`() async throws {
        try write(
            ".agents/skills/demo/SKILL.md",
            "---\nname: demo\ndescription: A demo.\nallowed-tools: Read\n---\n# Demo\n\nDo the thing.\n")
        let output = try await run(#"{"name":"demo"}"#)
        #expect(!output.isError)
        #expect(output.content.hasPrefix("Skill: demo (agents, user)\nDirectory: "))
        #expect(
            output.content.contains("relative to that directory") && output.content.contains("grants no permission"))
        #expect(output.content.hasSuffix("# Demo\n\nDo the thing."))
        #expect(!output.content.contains("allowed-tools"))
    }

    @Test func `from may be a string, a comma list, a spaced list or an array, and narrows`() async throws {
        try write(".agents/skills/same/SKILL.md", "---\nname: same\ndescription: d\n---\nfrom agents\n")
        try write(".claude/skills/same/SKILL.md", "---\nname: same\ndescription: d\n---\nfrom claude\n")
        #expect(try await run(#"{"name":"same"}"#).content.hasSuffix("from agents"))
        for from in [#""claude""#, #""claude, codex""#, #""codex claude""#, #"["claude"]"#, #"["Claude", "nonsense"]"#]
        {
            let output = try await run(#"{"name":"same","from":\#(from)}"#)
            #expect(output.content.hasSuffix("from claude"), "\(from)")
        }
    }

    @Test func `a bundled skill needs from to say bundled`() async throws {
        try write(".gemini/builtin/skills/builtin/SKILL.md", "---\nname: builtin\ndescription: d\n---\nbundled body\n")
        #expect(try await run(#"{"name":"builtin"}"#).isError)
        let output = try await run(#"{"name":"builtin","from":"bundled"}"#)
        #expect(output.content.hasSuffix("bundled body") && output.content.contains("(agy, bundled)"))
    }

    @Test func `a missing name is an error that lists what exists, and says which words from ignored`() async throws {
        try write(".agents/skills/swift/SKILL.md", "---\nname: swift\ndescription: d\n---\nb\n")
        let output = try await run(#"{"name":"nope","from":"wat"}"#)
        #expect(
            output.isError && output.content.contains("No skill is called \"nope\"")
                && output.content.contains("Available: swift."))
        #expect(output.content.contains("ignored: wat"))
    }

    @Test func `a skill that asked not to be loaded by the model is refused with a reason`() async throws {
        try write(
            ".agents/skills/quiet/SKILL.md",
            "---\nname: quiet\ndescription: d\ndisable-model-invocation: true\n---\nb\n")
        let output = try await run(#"{"name":"quiet"}"#)
        #expect(output.isError && output.content.contains("only loaded when the user asks"))
    }

    @Test func `a path in the name, or in from, reads nothing`() async throws {
        try write(".agents/skills/a/SKILL.md", "---\nname: a\ndescription: d\n---\nb\n")
        try write("secret.txt", "TOP SECRET")
        for json in [
            #"{"name":"../../secret.txt"}"#, #"{"name":"\#(home)/secret.txt"}"#, #"{"name":"a","from":"\#(home)"}"#,
            #"{"name":"a","from":"../.."}"#
        ] {
            let output = try await run(json)
            #expect(!output.content.contains("TOP SECRET"), "\(json)")
        }
        #expect(!String(decoding: tool().definition.inputSchema.bytes, as: UTF8.self).contains("path"))
    }

    @Test func `a skill whose file has gone is an error, not a crash`() async throws {
        try write(".agents/skills/gone/SKILL.md", "---\nname: gone\ndescription: d\n---\nb\n")
        let tool = tool()
        try FileManager.default.removeItem(atPath: home + "/.agents/skills/gone/SKILL.md")
        let output = await tool.run(try JSONObject(validating: Array(#"{"name":"gone"}"#.utf8)), in: context)
        #expect(output.isError && output.content.contains("could not be read"))
    }

    @Test func `arguments that do not decode are an error the model can read`() async throws {
        #expect(try await run(#"{"from":"claude"}"#).isError)
        #expect(try await run(#"{"name":5}"#).isError)
    }
}
