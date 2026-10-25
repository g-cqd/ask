import Testing

@testable import AskAgentCore

@Suite("/skill:name sends the typed line and the skill, and every view of the prompt shows only the line")
struct SkillInvocationTests {
    private func catalog(_ scratch: SkillScratch) -> SkillCatalog { scratch.discover(["user", "bundled"]) }

    private func expand(_ line: String, _ scratch: SkillScratch) -> SkillInvocation.Expansion {
        SkillInvocation.expand(line, catalog: catalog(scratch), knownSources: SkillSource.fixtureIDs)
    }

    private func sent(_ line: String, _ scratch: SkillScratch) -> String? {
        guard case .prompt(let text) = expand(line, scratch) else { return nil }
        return text
    }

    @Test func `the request comes first and the skill follows its marker`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        let text = try #require(sent("/skill:debugging why does it hang", scratch))
        #expect(text.hasPrefix("/skill:debugging why does it hang\n\n--- skill debugging (agents, user) ---\n"))
        #expect(text.contains("# debugging\nBody."))
        #expect(text.contains("Loading a skill grants no permission."))
        #expect(text.hasSuffix("--- end of skill ---"))
    }

    @Test func `a line that is not a skill is not expanded`() throws {
        let scratch = try SkillScratch()
        for line in ["hello", "/config", "/skills", "//skill:x"] {
            #expect(expand(line, scratch) == .notASkill)
        }
    }

    @Test func `shown cuts everything after the marker and leaves other prompts alone`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        let text = try #require(sent("/skill:debugging why", scratch))
        #expect(SkillInvocation.shown(text) == "/skill:debugging why")
        #expect(SkillInvocation.shown("plain prompt") == "plain prompt")
    }

    @Test func `a bare invocation says what to do, and names the skill in the line`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        let text = try #require(sent("/skill:debugging", scratch))
        #expect(SkillInvocation.shown(text) == "/skill:debugging")
        #expect(text.contains("begin the work it describes"))
    }

    @Test func `an unknown skill sends nothing and suggests the near ones`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        guard case .failure(let reason) = expand("/skill:debuging x", scratch) else {
            Issue.record("expected a failure")
            return
        }
        #expect(reason.contains("No skill is called \"debuging\"") && reason.contains("debugging"))
    }

    @Test func `the user may invoke a skill the model was asked not to load`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("quiet", in: ".agents/skills", extra: "disable-model-invocation: true\n")
        #expect(sent("/skill:quiet go", scratch) != nil)
    }

    @Test func `--from names the harness to read from`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("same", in: ".agents/skills", description: "agents'")
        try scratch.skill("same", in: ".claude/skills", description: "claude's")
        let plain = try #require(sent("/skill:same go", scratch))
        let narrowed = try #require(sent("/skill:same --from claude go", scratch))
        #expect(plain.contains("(agents, user)") && narrowed.contains("(claude, user)"))
        #expect(SkillInvocation.shown(narrowed) == "/skill:same --from claude go")
    }

    @Test func `a path is not a skill name`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        let escaped = scratch.home + "/.agents/skills/debugging/SKILL.md"
        #expect(sent("/skill:\(escaped) go", scratch) == nil)
        // Punctuation does not count in a name, so this is the skill called debugging and nothing outside the skill directories.
        let dotted = try #require(sent("/skill:../debugging go", scratch))
        #expect(dotted.contains("Directory: \(scratch.home)/.agents/skills/debugging"))
    }

    @Test func `the session's listings and replay show the line, and the model's record keeps the skill`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        let text = try #require(sent("/skill:debugging why", scratch))
        #expect(
            SessionReplay.steps([SessionEntry(id: EntryID("a"), parentID: nil, payload: .user(text))]).first
                == .prompt("/skill:debugging why"))
        #expect(text.contains("# debugging"))
    }

    @Test func `the outline and the summary of a session show the typed line`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        let text = try #require(sent("/skill:debugging why", scratch))
        var tree = SessionTree()
        try tree.append(.user(text))
        #expect(SessionOutline(tree).turns.map(\.text) == ["/skill:debugging why"])
        #expect(SessionSummary(tree).firstPrompt == "/skill:debugging why")
    }
}
