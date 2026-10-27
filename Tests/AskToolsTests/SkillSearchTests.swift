import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

@Suite("Skill discovery queries are bounded metadata searches, not file loads")
struct SkillSearchTests {
    private let home = FileManager.default.temporaryDirectory.appending(path: "ask-skillsearch-\(UUID().uuidString)")
        .path
    private let sources = [
        SkillSource(id: "agents", userRoots: [".agents/skills"], projectRoots: [".agents/skills"], bundledRoots: []),
        SkillSource(id: "other", userRoots: [".other/skills"], projectRoots: [], bundledRoots: [".bundled/skills"])
    ]

    private func make(
        _ name: String, description: String = "description", root: String = ".agents/skills", quiet: Bool = false
    ) throws {
        let directory = home + "/" + root + "/" + name
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try
            ("---\nname: \(name)\ndescription: \(description)\n" + (quiet ? "disable-model-invocation: true\n" : "")
            + "---\nPRIVATE BODY\n")
            .write(toFile: directory + "/SKILL.md", atomically: true, encoding: .utf8)
    }

    private func tool() -> SkillTool {
        let known = sources.map(\.id)
        let catalog = SkillDiscovery.discover(
            workingDirectory: home + "/project", home: home, sources: sources,
            selection: SkillSelection(tokens: ["user", "project", "bundled"], knownSources: known))
        return SkillTool(catalog: catalog, knownSources: known)
    }

    private func run(_ tool: SkillTool, _ json: String) async throws -> ToolOutput {
        await tool.run(try JSONObject(validating: Array(json.utf8)), in: ToolContext(workingDirectory: home))
    }

    @Test func `empty arguments browse a bounded stable list without loading any body`() async throws {
        for number in (1 ... 12).reversed() { try make(String(format: "skill%02d", number)) }
        let tool = tool()
        try FileManager.default.removeItem(atPath: home + "/.agents")
        let output = try await run(tool, "{}")
        #expect(!output.isError)
        #expect(output.content.components(separatedBy: "- skill").count - 1 == 8)
        #expect(output.content.contains("skill01") && output.content.contains("skill08"))
        #expect(!output.content.contains("skill09") && !output.content.contains("PRIVATE BODY"))
        #expect(!output.content.contains(home))
        #expect(try await run(tool, #"{"query":""}"#) == output)
    }

    @Test func `search uses full descriptions and ranks name matches before description matches`() async throws {
        try make("zebra", description: "unrelated")
        try make("alpha", description: String(repeating: "padding ", count: 20) + "zebra")
        let output = try await run(tool(), #"{"query":"ZEBRA"}"#)
        #expect(!output.isError)
        let zebra = try #require(output.content.range(of: "- zebra:"))
        let alpha = try #require(output.content.range(of: "- alpha:"))
        #expect(zebra.lowerBound < alpha.lowerBound)
    }

    @Test(arguments: ["deplyment", "deployxment", "deploymant", "deplyoment"])
    func `bounded edit distance finds misspelled skill names`(_ query: String) async throws {
        try make("deployment")
        try make("unrelated")
        let result = try await run(tool(), #"{"query":"\#(query)"}"#)
        #expect(result.content.contains("- deployment:") && !result.content.contains("- unrelated:"))
    }

    @Test func `literal name matches outrank fuzzy names and descriptions support typos`() async throws {
        try make("deploymant")
        try make("deployment")
        try make("release", description: "Infrastructure provisioning")
        let result = try await run(tool(), #"{"query":"deploymant"}"#)
        let literal = try #require(result.content.range(of: "- deploymant:"))
        let fuzzy = try #require(result.content.range(of: "- deployment:"))
        #expect(literal.lowerBound < fuzzy.lowerBound)
        #expect(try await run(tool(), #"{"query":"provisoning"}"#).content.contains("- release:"))
        #expect(!(try await run(tool(), #"{"query":"xy"}"#)).content.contains("- release:"))
    }

    @Test func `search honors source scope trust and invocation restrictions`() async throws {
        try make("shown")
        try make("quiet", quiet: true)
        try make("builtin", root: ".bundled/skills")
        try make("untrusted", root: "project/.agents/skills")
        try make("other", root: ".other/skills")
        let tool = tool()
        let normal = try await run(tool, #"{"query":""}"#)
        #expect(normal.content.contains("- shown:") && normal.content.contains("- other:"))
        for hidden in ["quiet", "builtin", "untrusted"] { #expect(!normal.content.contains("- \(hidden):")) }
        let narrowed = try await run(tool, #"{"query":"","from":"other"}"#)
        #expect(narrowed.content.contains("- other:") && !narrowed.content.contains("- shown:"))
        let bundled = try await run(tool, #"{"query":"","from":"bundled"}"#)
        #expect(bundled.content.contains("- builtin:") && !bundled.content.contains("- shown:"))
    }

    @Test func `name loading stays distinct from query and mixed modes are refused`() async throws {
        try make("demo")
        let tool = tool()
        #expect(try await run(tool, #"{"name":"demo"}"#).content.hasSuffix("PRIVATE BODY"))
        #expect(try await run(tool, #"{"name":"demo","query":"demo"}"#).isError)
        let missing = try await run(tool, #"{"query":"unmatched"}"#)
        #expect(!missing.isError && missing.content.contains("No skill matches"))
        #expect(try await run(tool, #"{"query":7}"#).isError)
    }
}
