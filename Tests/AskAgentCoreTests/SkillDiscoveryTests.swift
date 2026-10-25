import Foundation
import Testing

@testable import AskAgentCore

/// Skills are found in every harness's directories, once each, and read without being strict.
@Suite("Skills are discovered across harnesses, once each")
struct SkillDiscoveryTests {
    @Test func `skills in several harnesses' directories are all found, with where they came from`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("alpha", in: ".agents/skills")
        try scratch.skill("beta", in: ".claude/skills")
        try scratch.skill("gamma", in: ".codex/skills")
        try scratch.skill("delta", in: ".pi/agent/skills")
        try scratch.skill("epsilon", in: ".config/opencode/skill")
        try scratch.skill("zeta", in: "work/repo/.agents/skills")
        let catalog = scratch.discover()
        #expect(catalog.byName.map(\.name) == ["alpha", "beta", "delta", "epsilon", "gamma", "zeta"])
        let sources = Dictionary(
            uniqueKeysWithValues: catalog.skills.map { ($0.name, "\($0.source)/\($0.scope.rawValue)") })
        #expect(
            sources["alpha"] == "agents/user" && sources["epsilon"] == "opencode/user"
                && sources["zeta"] == "agents/project")
    }

    @Test func `eight harness directories that are links to one directory give each skill once`() throws {
        let scratch = try SkillScratch()
        for name in ["one", "two", "three"] { try scratch.skill(name, in: ".agent-harness/skills") }
        let canonical = scratch.home + "/.agent-harness/skills"
        for path in [
            ".claude/skills", ".agents/skills", ".codex/skills", ".pi/agent/skills", ".config/opencode/skills",
            ".vibe/skills",
            ".copilot/skills", ".gemini/config/skills"
        ] { try scratch.link(path, to: canonical) }
        let catalog = scratch.discover()
        #expect(catalog.skills.count == 3 && catalog.shadowed.isEmpty && catalog.skipped.isEmpty)
        #expect(catalog.roots.filter(\.exists).count == 8)
    }

    @Test func `a project's skill beats a user's of the same name, and the user's is reported, not offered`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("review", in: ".agents/skills", description: "the user's")
        try scratch.skill("review", in: "work/repo/.claude/skills", description: "the project's")
        let catalog = scratch.discover()
        #expect(catalog.skills.map(\.description) == ["the project's"])
        #expect(catalog.shadowed.map(\.description) == ["the user's"])
    }

    @Test func `the nearer project directory wins over a farther one`() throws {
        let scratch = try SkillScratch()
        try scratch.write("work/.git/HEAD", "")
        try scratch.write("work/repo/sub/.git/HEAD", "")
        try scratch.skill("x", in: "work/.agents/skills", description: "outer")
        try scratch.skill("x", in: "work/repo/sub/.agents/skills", description: "inner")
        let catalog = SkillDiscovery.discover(
            workingDirectory: scratch.project + "/sub", home: scratch.home, sources: SkillSource.fixture)
        #expect(catalog.skills.map(\.description) == ["inner"])
    }

    @Test func `two copies with the same bytes are one skill with no report`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("same", in: ".agents/skills")
        try scratch.skill("same", in: ".claude/skills")
        let catalog = scratch.discover()
        #expect(catalog.skills.count == 1 && catalog.shadowed.isEmpty)
    }

    @Test func `bundled skills are not found unless asked for, and then they are found`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("mine", in: ".agents/skills")
        try scratch.skill("builtin", in: ".gemini/antigravity-cli/builtin/skills")
        #expect(scratch.discover().skills.map(\.name) == ["mine"])
        #expect(scratch.discover(["bundled"]).skills.map(\.name) == ["builtin"])
        #expect(
            Set(scratch.discover(["agy", "bundled"]).skills.map(\.name)) == ["builtin"],
            "the bundled skills of the harness named")
        #expect(Set(scratch.discover(["agents", "agy", "bundled"]).skills.map(\.name)) == ["mine", "builtin"])
        #expect(scratch.discover(["bundled"]).skills.first?.scope == .bundled)
    }

    @Test func `naming harnesses or scopes narrows, and nothing else`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("a", in: ".agents/skills")
        try scratch.skill("c", in: ".claude/skills")
        try scratch.skill("p", in: "work/repo/.codex/skills")
        #expect(scratch.discover(["claude"]).skills.map(\.name) == ["c"])
        #expect(Set(scratch.discover(["claude", "codex"]).skills.map(\.name)) == ["c", "p"])
        #expect(scratch.discover(["project"]).skills.map(\.name) == ["p"])
        #expect(Set(scratch.discover(["user"]).skills.map(\.name)) == ["a", "c"])
        #expect(scratch.discover(["nonsense"]).skills.count == 3, "an unknown word narrows nothing")
    }

    @Test func `a quoted name, a missing head, a missing description and a hidden group directory are all read`() throws
    {
        let scratch = try SkillScratch()
        let root = ".agents/skills"
        try scratch.write(root + "/quoted/SKILL.md", "---\nname: \"openai-docs\"\ndescription: d\n---\n")
        try scratch.write(root + "/headless/SKILL.md", "# Headless\n\nDoes the thing\nover two lines.\n\nMore.\n")
        try scratch.write(root + "/nodescription/SKILL.md", "---\nname: nodescription\n---\nFirst line of the body.\n")
        try scratch.skill("grouped", in: root + "/.system")
        let byName = Dictionary(uniqueKeysWithValues: scratch.discover().skills.map { ($0.name, $0) })
        #expect(
            byName["openai-docs"] != nil
                && byName["openai-docs"]?.diagnostics.contains { $0.contains("differs from its directory") } == true)
        #expect(byName["headless"]?.description == "Does the thing over two lines.")
        #expect(byName["nodescription"]?.description == "First line of the body.")
        #expect(byName["grouped"] != nil)
    }

    @Test func `a bare Markdown file is a skill only with a description, and a README never is`() throws {
        let scratch = try SkillScratch()
        try scratch.write(".agents/skills/bare.md", "---\ndescription: A bare one.\n---\nBody\n")
        try scratch.write(".agents/skills/plain.md", "Just notes.\n")
        try scratch.write(".agents/skills/README.md", "---\ndescription: readme\n---\n")
        let catalog = scratch.discover()
        #expect(catalog.skills.map(\.name) == ["bare"])
        #expect(catalog.skipped.count == 1 && catalog.skipped[0].contains("plain.md"))
    }

    @Test func `odd names are loaded with a note, and a skill that asks not to be offered is marked`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("Odd_Name", in: ".agents/skills", extra: "disable-model-invocation: true\n")
        let skill = try #require(scratch.discover().skills.first)
        #expect(skill.name == "Odd_Name" && !skill.modelInvocable)
        #expect(skill.diagnostics.contains { $0.contains("outside the Agent Skills form") })
        #expect(scratch.discover().estimatedAdvertisementTokens == 0)
    }

    @Test func `tools and models in a skill are read, shown, and unknown names are kept`() throws {
        let scratch = try SkillScratch()
        try scratch.skill(
            "t", in: ".agents/skills",
            extra: "allowed-tools: Read, Bash(git diff:*), LSP\nmodel: opus\n# fallback_models: sonnet\nlicense: MIT\n")
        let skill = try #require(scratch.discover().skills.first)
        #expect(skill.tools.map(\.token) == ["Read", "Bash(git diff:*)", "LSP"])
        #expect(skill.tools.map(\.ask) == ["read", "bash", nil])
        #expect(skill.models.tokens == ["opus", "sonnet"] && skill.otherKeys == ["license"])
        #expect(skill.diagnostics.contains { $0.contains("LSP") })
    }

    @Test func `a binary file and a symlink loop are survived`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("ok", in: ".agents/skills")
        try Data([0x53, 0x00, 0x4b])
            .write(to: URL(fileURLWithPath: try scratch.write(".agents/skills/bin/SKILL.md", "x")))
        try scratch.link(".agents/skills/loop", to: scratch.home + "/.agents/skills")
        let catalog = scratch.discover()
        #expect(catalog.skills.map(\.name) == ["ok"])
        #expect(catalog.skipped.contains { $0.contains("not text") })
    }

    @Test func `outside the home directory only the working directory is a project`() throws {
        let scratch = try SkillScratch()
        let outside = FileManager.default.temporaryDirectory.appending(path: "ask-out-\(UUID().uuidString)/repo").path
        try FileManager.default.createDirectory(atPath: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: (outside as NSString).deletingLastPathComponent) }
        #expect(SkillDiscovery.projectDirectories(from: outside, home: scratch.home) == [outside])
        #expect(SkillDiscovery.projectDirectories(from: scratch.home, home: scratch.home).isEmpty)
    }

    @Test func `the advertisement is cut at the limit and the skill keeps its whole description`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("long", in: ".agents/skills", description: String(repeating: "word ", count: 400))
        let skill = try #require(scratch.discover().skills.first)
        #expect(skill.description.count > Skill.advertisedDescriptionLimit)
        #expect(skill.advertisement.count < Skill.advertisedDescriptionLimit + 200 && skill.advertisement.contains("…"))
        #expect(skill.diagnostics.contains { $0.contains("cuts it") })
    }
}
