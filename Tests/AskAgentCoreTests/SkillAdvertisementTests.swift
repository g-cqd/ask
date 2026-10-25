import Testing

@testable import AskAgentCore

@Suite("The system prompt lists skills in a stable order, up to a limit, and says how many it left out")
struct SkillAdvertisementTests {
    private func catalog(_ names: [String], extra: (SkillScratch) throws -> Void = { _ in }) throws -> (
        SkillScratch, SkillCatalog
    ) {
        let scratch = try SkillScratch()
        for name in names { try scratch.skill(name, in: ".agents/skills", description: "About \(name).") }
        return (scratch, scratch.discover(["user", "bundled"]))
    }

    @Test func `each skill is a line of name, description and path, after an instruction, and nothing else`() throws {
        let (scratch, catalog) = try catalog(["beta", "alpha"])
        let block = try #require(SkillAdvertisement.block(for: catalog, limit: 32))
        let lines = block.split(separator: "\n").map(String.init)
        #expect(lines.count == 3 && lines[0].hasPrefix("Skills are specialised instructions"))
        #expect(lines[1] == "- alpha: About alpha. (\(scratch.home)/.agents/skills/alpha/SKILL.md)")
        #expect(lines[2].hasPrefix("- beta: About beta."))
        #expect(block.contains("grants a permission"))
    }

    @Test func `the order is by name whatever order they were found in, and the bytes are the same twice`() throws {
        let scratch = try SkillScratch()
        // Found in the order agents, claude, codex: c, a, b. Listed by name: a, b, c.
        try scratch.skill("c", in: ".agents/skills")
        try scratch.skill("a", in: ".claude/skills")
        try scratch.skill("b", in: ".codex/skills")
        let catalog = scratch.discover(["user"])
        #expect(catalog.skills.map(\.name) == ["c", "a", "b"])
        let first = try #require(SkillAdvertisement.block(for: catalog, limit: 32))
        let names = first.split(separator: "\n").dropFirst().map { String($0.prefix(5)) }
        #expect(names == ["- a: ", "- b: ", "- c: "])
        #expect(SkillAdvertisement.block(for: scratch.discover(["user"]), limit: 32) == first)
    }

    @Test func `over the limit it keeps the first by precedence, lists them by name, and counts the rest`() throws {
        let (scratch, _) = try catalog([])
        for name in ["d", "c", "b", "a"] { try scratch.skill(name, in: ".agents/skills") }
        let catalog = scratch.discover(["user"])
        let block = try #require(SkillAdvertisement.block(for: catalog, limit: 2))
        let lines = block.split(separator: "\n")
        #expect(lines.count == 4 && lines.last?.contains("2 more skills are not listed here") == true)
        #expect(
            lines.dropFirst().prefix(2).map { $0.prefix(5) }
                == lines.dropFirst().prefix(2).map { $0.prefix(5) }.sorted())
        let one = try #require(SkillAdvertisement.block(for: catalog, limit: 3))
        #expect(one.contains("1 more skill is not listed here"))
        #expect(!(try #require(SkillAdvertisement.block(for: catalog, limit: 4))).contains("not listed"))
    }

    @Test func `a limit of zero lists none and still says they exist`() throws {
        let (_, catalog) = try catalog(["a", "b"])
        let block = try #require(SkillAdvertisement.block(for: catalog, limit: 0))
        #expect(block.split(separator: "\n").count == 2 && block.contains("2 more skills are not listed here"))
    }

    @Test func `bundled skills and skills that ask not to be offered are never listed`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("shown", in: ".agents/skills")
        try scratch.skill("quiet", in: ".agents/skills", extra: "disable-model-invocation: true\n")
        try scratch.skill("builtin", in: ".gemini/antigravity-cli/builtin/skills")
        let block = try #require(SkillAdvertisement.block(for: scratch.discover(["user", "bundled"]), limit: 32))
        #expect(block.contains("- shown:") && !block.contains("quiet") && !block.contains("builtin"))
    }

    @Test func `nothing to advertise is no block at all`() throws {
        let scratch = try SkillScratch()
        #expect(SkillAdvertisement.block(for: scratch.discover(), limit: 32) == nil)
        try scratch.skill("only-quiet", in: ".agents/skills", extra: "disable-model-invocation: true\n")
        #expect(SkillAdvertisement.block(for: scratch.discover(), limit: 32) == nil)
    }

    @Test func `a long description is cut in the line and whole in the skill`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("long", in: ".agents/skills", description: String(repeating: "word ", count: 400))
        let block = try #require(SkillAdvertisement.block(for: scratch.discover(), limit: 32))
        #expect(block.contains("…") && block.count < 1_800)
    }
}
