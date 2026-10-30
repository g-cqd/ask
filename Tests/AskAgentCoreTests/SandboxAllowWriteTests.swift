import Testing

@testable import AskAgentCore

/// `sandbox.allowWrite` (security audit 2026-10-29): places protected from writing the person chooses to open, in their own file only;
/// a relative entry is relative to the project, so `.git/config` names every repository's.
@Suite("sandbox.allowWrite")
struct SandboxAllowWriteTests {
    @Test func `it is read from the person's file and refused in a project's`() throws {
        let json = #"{"sandbox": {"allowWrite": ["~/.zshrc", ".git/config"]}}"#
        let file = try ConfigurationFile.parse(Array(json.utf8), path: "c.json")
        #expect(file.sandbox?.allowWrite == ["~/.zshrc", ".git/config"])
        #expect(throws: (any Error).self) {
            try ConfigurationFile.parse(Array(json.utf8), path: "p.json", isProject: true)
        }
    }

    @Test func `entries are expanded against the home and the workspace`() {
        #expect(SandboxSection.expandWrite("~/.zshrc", home: "/h", workspace: "/w") == "/h/.zshrc")
        #expect(SandboxSection.expandWrite(".git/config", home: "/h", workspace: "/w") == "/w/.git/config")
        #expect(SandboxSection.expandWrite("/abs", home: "/h", workspace: "/w") == "/abs")
    }
}
