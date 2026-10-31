import Foundation
import Testing

@testable import AskAgentCore

/// A project's skill is text from a repository; a link in it can point anywhere on the machine. A project's skill is read only when its
/// file is inside the project, so trusting a project's skills can never hand the model a file the sandbox would have asked about.
@Suite("A project's skill that links outside the project is not read")
struct SkillLinkTests {
    @Test func `a project skill linked to a file outside the project is skipped, never offered for trust`() throws {
        let scratch = try SkillScratch()
        let secret = try scratch.write("secrets/credentials", "[default]\naws_secret_access_key = hunter2\n")
        try scratch.link("work/repo/.agents/skills/setup/SKILL.md", to: secret)
        let catalog = scratch.discover()
        #expect(catalog.skills.isEmpty)
        #expect(catalog.untrusted.isEmpty)
        #expect(catalog.skipped.contains { $0.contains("setup") && $0.contains("outside the project") })
        #expect(!catalog.skipped.joined().contains("hunter2"))
    }

    @Test func `a project skill directory linked outside the project is skipped too`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("elsewhere", in: "outside/skills")
        try scratch.link("work/repo/.agents/skills/elsewhere", to: scratch.home + "/outside/skills/elsewhere")
        let catalog = scratch.discover()
        #expect(catalog.skills.isEmpty && catalog.untrusted.isEmpty)
        #expect(catalog.skipped.contains { $0.contains("outside the project") })
    }

    @Test func `a project's skills folder linked to the user's own still finds them, as the user's`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("mine", in: ".agents/skills")
        try scratch.link("work/repo/.agents/skills", to: scratch.home + "/.agents/skills")
        let catalog = scratch.discover()
        #expect(catalog.skills.map(\.name) == ["mine"])
        #expect(catalog.skills.first?.scope == .user)
    }

    @Test func `a link that stays inside the project is followed as before`() throws {
        let scratch = try SkillScratch()
        try scratch.skill("shared", in: "work/repo/tools/skills")
        try scratch.link("work/repo/.agents/skills/shared", to: scratch.project + "/tools/skills/shared")
        let catalog = scratch.discover()
        #expect(catalog.skills.map(\.name) == ["shared"])
        #expect(catalog.skills.first?.scope == .project)
    }
}
