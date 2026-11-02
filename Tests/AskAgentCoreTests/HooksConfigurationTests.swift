import Testing

@testable import AskAgentCore

/// The `hooks` section (roadmap 0192, ADR-0143): how many times hooks may continue one run. Only the person's own file sets it, since a
/// repository must not make runs go on longer.
@Suite("The hooks section limits continues, and only the person's file sets it")
struct HooksConfigurationTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    @Test func `the file reads maxContinues, and zero turns continuing off`() throws {
        #expect(try parse("{hooks:{maxContinues:5}}").hooks == HooksSection(maxContinues: 5))
        #expect(try parse("{hooks:{maxContinues:0}}").hooks?.maxContinues == 0)
    }

    @Test func `unset, a run may be continued 3 times`() {
        #expect(Configuration.defaults.hooks.value.continues == 3)
        let settings = AgentSettings(model: "m", maximumTokens: 1, systemPrompt: [], maximumTurns: 1)
        #expect(HooksSection.defaultMaxContinues == settings.maximumHookContinues)
    }

    @Test func `an unknown key, a negative or huge count and a wrong type are refused by name`() throws {
        #expect(throws: ConfigurationError.self) { try parse("{hooks:{claude:true}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "hooks.maxContinues",
                reason: "must be from 0 to 100"
            )
        ) { try parse("{hooks:{maxContinues:-1}}") }
        #expect(
            throws: ConfigurationError.outOfRange(
                path: "c.json",
                key: "hooks.maxContinues",
                reason: "must be from 0 to 100"
            )
        ) { try parse("{hooks:{maxContinues:101}}") }
        #expect(try parse("{hooks:{maxContinues:100}}").hooks?.maxContinues == 100)
        #expect(throws: ConfigurationError.self) { try parse("{hooks:{maxContinues:'3'}}") }
    }

    @Test func `a project's file may not set it`() {
        #expect(throws: ConfigurationError.self) { try parse("{hooks:{maxContinues:1}}", project: true) }
    }

    @Test func `a layer that sets it wins, one that does not leaves it`() {
        var file = ConfigurationFile()
        file.hooks = HooksSection(maxContinues: 7)
        let user = Configuration.defaults.applying(file, from: .file("user"))
        #expect(user.hooks.value.continues == 7 && user.hooks.source == .file("user"))
        file.hooks = HooksSection()
        let next = user.applying(file, from: .file("other"))
        #expect(next.hooks.value.continues == 7)
    }

    @Test func `the file says it sets hooks, and a change is reported`() throws {
        let file = try parse("{hooks:{maxContinues:2}}")
        #expect(file.sets("hooks") && !ConfigurationFile().sets("hooks"))
        let changed = Configuration.defaults.applying(file, from: .file("user"))
        #expect(changed.changes(from: .defaults).contains { $0.contains("hooks") })
    }
}
