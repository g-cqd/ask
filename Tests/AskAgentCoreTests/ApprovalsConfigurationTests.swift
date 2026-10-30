import Testing

@testable import AskAgentCore

/// `approvals` in a configuration file (roadmap 0134): the person's own file only.
@Suite("The approvals section")
struct ApprovalsConfigurationTests {
    @Test func `it is read, shown, and refused in a project's file`() throws {
        let json =
            #"{"approvals": {"default": "allow", "allow": ["bash"], "ask": ["mcp__x__*"], "scope": "narrowing-only"}}"#
        let file = try ConfigurationFile.parse(Array(json.utf8), path: "c.json")
        #expect(
            file.approvals
                == ApprovalsSection(defaultMode: .allow, allow: ["bash"], ask: ["mcp__x__*"], scope: .narrowingOnly))
        let configured = Configuration.defaults.applying(file, from: .file("/u/config.json"))
        #expect(configured.approvals.value.defaultMode == .allow)
        #expect(configured.changes(from: .defaults).first?.hasPrefix("approvals: ") == true)
        #expect(throws: (any Error).self) {
            try ConfigurationFile.parse(Array(json.utf8), path: "p.json", isProject: true)
        }
    }

    @Test func `unknown keys and values are refused`() {
        for json in [
            #"{"approvals": {"default": "sometimes"}}"#, #"{"approvals": {"scope": "all"}}"#,
            #"{"approvals": {"deny": []}}"#,
            #"{"approvals": {"allow": "bash"}}"#
        ] {
            #expect(throws: (any Error).self, "\(json)") {
                try ConfigurationFile.parse(Array(json.utf8), path: "c.json")
            }
        }
    }
}
