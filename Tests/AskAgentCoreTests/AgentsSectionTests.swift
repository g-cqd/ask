import Testing

@testable import AskAgentCore

/// The `agents` section (roadmap 0063, ADR-0146): off unless the person's own file turns it on; a project's may turn it off, never on.
@Suite("Subagents are off unless the person turns them on")
struct AgentsSectionTests {
    private func agents(_ json: String, project: Bool = false) throws -> AgentsSection? {
        try ConfigurationFile.parse(Array(#"{"agents": \#(json)}"#.utf8), path: "test", isProject: project).agents
    }

    @Test func `off, read-only and thirty turns when nothing says`() {
        let section = AgentsSection()
        #expect(!section.isEnabled && !section.writes && section.turns == 30)
    }

    @Test func `the person's own file turns them on, and may allow writes and set the turns`() throws {
        let section = try #require(try agents(#"{"enabled": true, "allowWrites": true, "maxTurns": 12}"#))
        #expect(section.isEnabled && section.writes && section.turns == 12)
        #expect(throws: ConfigurationError.self) { try agents(#"{"maxTurns": 0}"#) }
    }

    @Test func `a project's file may turn them off, never on, and its off wins`() throws {
        #expect(throws: ConfigurationError.self) { try agents(#"{"enabled": true}"#, project: true) }
        #expect(throws: ConfigurationError.self) { try agents(#"{"allowWrites": true}"#, project: true) }
        let off = try #require(try agents(#"{"enabled": false}"#, project: true))
        let person = try #require(try agents(#"{"enabled": true}"#))
        #expect(!person.layered(with: off).isEnabled)
    }

    @Test func `other harnesses' definitions only when the person's own file says so`() throws {
        #expect(!AgentsSection().readsOtherHarnesses)
        #expect(try agents(#"{"otherHarnesses": true}"#)?.readsOtherHarnesses == true)
        #expect(throws: ConfigurationError.self) { try agents(#"{"otherHarnesses": true}"#, project: true) }
    }
}
