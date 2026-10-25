import Testing

@testable import AskAgentCore

@Suite("A skill is found by name among the ones a selection allows")
struct SkillLookupTests {
    private func lookup(_ scratch: SkillScratch, _ name: String, from words: [String] = []) -> SkillLookup {
        scratch.discover(["user", "bundled"])
            .find(
                name, selection: SkillSelection(tokens: words, knownSources: SkillSource.fixtureIDs))
    }

    @Test func `a name is found without regard to case or punctuation`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("code-review", in: ".agents/skills")
        for spelling in ["code-review", "Code-Review", "code_review", "Code Review", "codereview"] {
            guard case .found(let skill) = lookup(scratch, spelling) else {
                Issue.record("not found: \(spelling)")
                continue
            }
            #expect(skill.name == "code-review")
        }
    }

    @Test func `a skill that lost its name is reached by naming its harness`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("same", in: ".agents/skills", description: "agents'")
        try scratch.skill("same", in: ".claude/skills", description: "claude's")
        guard case .found(let first) = lookup(scratch, "same"),
            case .found(let second) = lookup(scratch, "same", from: ["claude"])
        else {
            Issue.record("not found")
            return
        }
        #expect(first.description == "agents'" && second.description == "claude's")
    }

    @Test func `bundled skills are found only when from says bundled`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("builtin", in: ".gemini/antigravity-cli/builtin/skills")
        guard case .missing = lookup(scratch, "builtin") else {
            Issue.record("found without asking")
            return
        }
        guard case .found(let skill) = lookup(scratch, "builtin", from: ["bundled"]) else {
            Issue.record("not found")
            return
        }
        #expect(skill.scope == .bundled)
    }

    @Test func `a skill that asked not to be loaded by the model says so`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("quiet", in: ".agents/skills", extra: "disable-model-invocation: true\n")
        guard case .onlyWhenAsked(let skill) = lookup(scratch, "quiet") else {
            Issue.record("not refused")
            return
        }
        #expect(skill.name == "quiet")
    }

    @Test func `a missing name gets the nearest names, and every name when none is near`() throws {
        let scratch = try SkillScratch()
        for name in ["swift", "swiftui", "testing"] { try scratch.skill(name, in: ".agents/skills") }
        guard case .missing(let near) = lookup(scratch, "swif") else {
            Issue.record("found")
            return
        }
        #expect(near == ["swift", "swiftui"])
        guard case .missing(let all) = lookup(scratch, "nothing-like-it") else {
            Issue.record("found")
            return
        }
        #expect(all == ["swift", "swiftui", "testing"])
    }

    @Test func `a path or an empty name is never a skill`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("a", in: ".agents/skills")
        for name in ["", "  ", "../../etc/passwd", "/Users/x/.agents/skills/a/SKILL.md"] {
            guard case .missing = lookup(scratch, name) else {
                Issue.record("found: \(name.debugDescription)")
                return
            }
        }
    }
}
