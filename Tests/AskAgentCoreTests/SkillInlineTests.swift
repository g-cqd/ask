import Foundation
import Testing

@testable import AskAgentCore

/// Roadmap 0185: a `/skill:name` that starts any word of a message, not only the first, attaches the skill; the text the model reads
/// keeps the token where it was typed.
@Suite("A skill named in the middle of a message is attached once, in order, and an unknown name stays text")
struct SkillInlineTests {
    private func sent(_ line: String, _ scratch: SkillScratch) -> String? {
        let catalog = scratch.discover(["user", "bundled"])
        guard
            case .prompt(let text) = SkillInvocation.expand(
                line,
                catalog: catalog,
                knownSources: SkillSource.fixtureIDs
            )
        else {
            return nil
        }
        return text
    }

    private func attached(_ text: String) -> [String] {
        text.components(separatedBy: SkillInvocation.marker).dropFirst().map { String($0.prefix { $0 != " " }) }
    }

    @Test func `skills named mid-message are attached after the line, each once, in the order named`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        try scratch.skill("review", in: ".agents/skills")
        let text = try #require(
            sent("fix the hang with /skill:debugging, then /skill:review it, and /skill:debugging again", scratch)
        )
        #expect(
            text.hasPrefix(
                "fix the hang with /skill:debugging, then /skill:review it, and /skill:debugging again\n\n--- skill "
            )
        )
        #expect(attached(text) == ["debugging", "review"])
        #expect(
            SkillInvocation.shown(text)
                == "fix the hang with /skill:debugging, then /skill:review it, and /skill:debugging again"
        )
    }

    @Test func `a leading skill and an inline one are both attached, the leading one first`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        try scratch.skill("review", in: ".agents/skills")
        let text = try #require(sent("/skill:review this, as /skill:debugging says", scratch))
        #expect(attached(text) == ["review", "debugging"])
    }

    @Test func `an unknown name mid-message stays text, and a message with no known skill is not one`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        let text = try #require(sent("use /skill:nothing and /skill:debugging", scratch))
        #expect(attached(text) == ["debugging"])
        #expect(
            SkillInvocation.expand("use /skill:nothing here", catalog: scratch.discover(["user"]), knownSources: [])
                == .notASkill
        )
    }

    @Test func `a slash inside a word never names a skill`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("debugging", in: ".agents/skills")
        for line in [
            "see a/skill:debugging", "https://x.dev/skill:debugging", "path:/skill:debugging", "(/skill:debugging)"
        ] {
            #expect(sent(line, scratch) == nil, "\(line)")
        }
        #expect(SkillInvocation.asksForSkill("see a/skill:debugging") == false)
        #expect(SkillInvocation.asksForSkill("then /skill:debugging") == true)
    }
}
