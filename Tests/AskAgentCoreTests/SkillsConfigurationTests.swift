import Testing

@testable import AskAgentCore

@Suite("The skills section configures what the model is told, and a project can only turn it off")
struct SkillsConfigurationTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    @Test func `a file reads all three keys and reports them`() throws {
        let file = try parse("{skills:{enabled:true,maxListed:12,sources:['claude','bundled']}}")
        #expect(file.skills == SkillsSection(enabled: true, maxAdvertised: 12, sources: ["claude", "bundled"]))
        #expect(file.skills?.description == "enabled true, maxListed 12, sources claude, bundled")
    }

    @Test func `the default limit is the owner's 32`() {
        #expect(SkillsSection.defaultMaxAdvertised == 32 && SkillsSection().isEmpty)
    }

    @Test func `an unknown key, a negative limit and a wrong type are refused by name`() {
        #expect(throws: ConfigurationError.self) { try parse("{skills:{nope:1}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json", key: "skills.maxListed", reason: "must be 0 or more")
        ) { try parse("{skills:{maxListed:-1}}") }
        #expect(throws: ConfigurationError.self) { try parse("{skills:{sources:'claude'}}") }
    }

    @Test func `zero is allowed: nothing listed, the tool still there`() throws {
        #expect(try parse("{skills:{maxListed:0}}").skills?.maxAdvertised == 0)
    }

    @Test func `a project's file may turn skills off and nothing else`() throws {
        #expect(try parse("{skills:{enabled:false}}", project: true).skills?.enabled == false)
        #expect(throws: ConfigurationError.self) { try parse("{skills:{enabled:true}}", project: true) }
        #expect(throws: ConfigurationError.self) { try parse("{skills:{maxListed:5}}", project: true) }
        #expect(throws: ConfigurationError.self) { try parse("{skills:{sources:['codex']}}", project: true) }
    }

    @Test func `layers replace the keys they set and leave the others`() {
        let user = ConfigurationFile(skills: SkillsSection(enabled: true, maxAdvertised: 10, sources: ["claude"]))
        let project = ConfigurationFile(skills: SkillsSection(enabled: false))
        let combined = Configuration.defaults.applying(user, from: .file("u")).applying(project, from: .file("p"))
        #expect(combined.skills.value == SkillsSection(enabled: false, maxAdvertised: 10, sources: ["claude"]))
        #expect(combined.changes(from: .defaults).contains { $0.hasPrefix("skills:") })
    }

    @Test func `skills is a known key`() {
        #expect(ConfigurationFile.keys.contains("skills") && ConfigurationFile(skills: SkillsSection()).sets("skills"))
    }
}
