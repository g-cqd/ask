import Foundation
import Testing

@testable import AskAgentCore

/// ask's own agent definitions (roadmap 0063 phase 3, ADR-0146): Markdown with a head, read by the permissive reader skills use. The
/// body is what the subagent is told before its task; `tools` only narrows; `model` is a preference.
@Suite("An agent definition is read from Markdown with a head")
struct AgentDefinitionTests {
    @Test func `its name, description, instructions, tools and models`() throws {
        let text =
            "---\nname: reviewer\ndescription: Reviews a diff.\ntools: Read, Grep\nmodel: haiku\n---\nYou review code carefully.\n"
        let definition = try #require(AgentDefinition.read(file: "/a/agents/x.md", text: text))
        #expect(definition.name == "reviewer" && definition.description == "Reviews a diff.")
        #expect(definition.instructions == "You review code carefully.")
        #expect(definition.tools.map(\.token) == ["Read", "Grep"] && definition.tools.first?.ask == "read")
        #expect(definition.models.tokens == ["haiku"])
    }

    @Test func `the file's name stands in for a name, the body's first paragraph for a description`() throws {
        let definition = try #require(
            AgentDefinition.read(file: "/a/agents/linter.md", text: "Checks the style of a change.\n\nMore.")
        )
        #expect(definition.name == "linter" && definition.description == "Checks the style of a change.")
        #expect(definition.tools.isEmpty, "no tools named: it narrows nothing")
    }

    @Test func `a file that says nothing is no definition`() {
        #expect(AgentDefinition.read(file: "/a/agents/empty.md", text: "---\nname: e\n---\n") == nil)
    }

    @Test func `discovery reads bare Markdown files, the first root's name wins, and a README is not one`() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "agents-\(UUID().uuidString)").path
        let first = base + "/one"
        let second = base + "/two"
        for directory in [first, second] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(atPath: base) }
        try "---\ndescription: First.\n---\nA.".write(toFile: first + "/alpha.md", atomically: true, encoding: .utf8)
        try "---\ndescription: Second.\n---\nB.".write(toFile: second + "/alpha.md", atomically: true, encoding: .utf8)
        try "---\ndescription: Beta.\n---\nC.".write(toFile: second + "/beta.md", atomically: true, encoding: .utf8)
        try "Read me.".write(toFile: first + "/README.md", atomically: true, encoding: .utf8)
        try "not markdown".write(toFile: first + "/notes.txt", atomically: true, encoding: .utf8)
        let found = AgentDiscovery.definitions(in: [first, second, base + "/missing"])
        #expect(found.map(\.name) == ["alpha", "beta"] && found.first?.description == "First.")
    }

    @Test func `a project's definitions count only as trusted, each file as its bytes are now`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "project-agents-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fixer = root + "/fixer.md"
        let other = root + "/other.md"
        try "---\ndescription: Fixes.\n---\nFix it.".write(toFile: fixer, atomically: true, encoding: .utf8)
        try "---\ndescription: Other.\n---\nDo it.".write(toFile: other, atomically: true, encoding: .utf8)
        var trust = ProjectTrust()
        let seen = AgentDiscovery.projectDefinitions(in: root, trust: trust)
        #expect(seen.trusted.isEmpty && seen.untrusted.map(\.name) == ["fixer", "other"], "nothing trusted yet")
        let fixerDefinition = try #require(seen.untrusted.first)
        trust.trust(fixerDefinition.realFile, digest: fixerDefinition.digest)
        #expect(AgentDiscovery.projectDefinitions(in: root, trust: trust).trusted.map(\.name) == ["fixer"])
        try "---\ndescription: Fixes, changed.\n---\nFix it.".write(toFile: fixer, atomically: true, encoding: .utf8)
        #expect(
            AgentDiscovery.projectDefinitions(in: root, trust: trust).trusted.isEmpty,
            "a changed file is untrusted again"
        )
    }

    @Test func `a Codex definition is TOML, its instructions under developer_instructions`() throws {
        let text = #"""
            name = "code-reviewer"
            description = "Reviews a change."
            model = "gpt-6-astra"
            developer_instructions = '''
            You review one change and report findings.
            '''
            """#
        let definition = try #require(AgentDefinition.read(file: "/h/.codex/agents/code-reviewer.toml", text: text))
        #expect(definition.name == "code-reviewer" && definition.description == "Reviews a change.")
        #expect(
            definition.instructions == "You review one change and report findings."
                && definition.models.tokens == ["gpt-6-astra"]
        )
    }

    @Test func `a Copilot file's name drops .agent, and discovery reads TOML too`() throws {
        let copilot = try #require(
            AgentDefinition.read(file: "/h/.copilot/agents/committer.agent.md", text: "Commits.\n")
        )
        #expect(copilot.name == "committer")
        let root = FileManager.default.temporaryDirectory.appending(path: "toml-agents-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        try "description = \"T.\"\ndeveloper_instructions = \"Do.\"\n"
            .write(toFile: root + "/t.toml", atomically: true, encoding: .utf8)
        #expect(AgentDiscovery.definitions(in: [root]).map(\.name) == ["t"])
    }
}
