import Testing

@testable import AskAgentCore

@Suite("The skills report says what was found and what was odd")
struct SkillReportTests {
    @Test func `it lists skills by name with their source, the notes, and the cost of advertising them`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("zeta", in: ".agents/skills")
        try scratch.skill("Alpha_Odd", in: ".claude/skills", extra: "allowed-tools: Read, LSP\n")
        let catalog = scratch.discover()
        let lines = SkillReport(catalog: catalog, selection: .standard, verbose: false).lines
        #expect(lines[0].hasPrefix("2 skills · 0 shadowed · 0 skipped · advertising them would cost about"))
        #expect(lines[1].contains("Alpha_Odd") && lines[1].contains("claude/user"))
        #expect(lines.contains { $0.contains("note: the name \"Alpha_Odd\" is outside") })
        #expect(lines.contains { $0.contains("zeta") && $0.contains("agents/user") })
        #expect(!lines.contains { $0.contains("searched:") })
    }

    @Test func `verbose adds tools as ask reads them, models, other fields and every directory searched`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("t", in: ".agents/skills", extra: "allowed-tools: Read, LSP\nmodel: opus\nlicense: MIT\n")
        let lines = SkillReport(catalog: scratch.discover(), selection: .standard, verbose: true).lines
        #expect(lines.contains { $0.contains("tools (shown, never honoured): read, ?LSP") })
        #expect(
            lines.contains { $0.contains("models: opus") } && lines.contains { $0.contains("other fields: license") })
        #expect(lines.contains("searched:") && lines.contains { $0.contains("absent") && $0.contains(".codex/skills") })
    }

    @Test func `a name taken by another skill and a word it did not understand are both said`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("same", in: ".agents/skills", description: "one")
        try scratch.skill("same", in: ".claude/skills", description: "two")
        let selection = SkillSelection(tokens: ["agents", "claude", "wat"], knownSources: SkillSource.fixtureIDs)
        let catalog = SkillDiscovery.discover(
            workingDirectory: scratch.project, home: scratch.home, sources: SkillSource.fixture, selection: selection)
        let lines = SkillReport(catalog: catalog, selection: selection, verbose: false).lines
        #expect(lines.contains("not a harness or a scope, so ignored: wat"))
        #expect(lines.contains { $0.hasPrefix("name taken by an earlier skill") })
        #expect(lines.contains { $0.contains("claude/user") && $0.contains(".claude/skills/same") })
    }
}
