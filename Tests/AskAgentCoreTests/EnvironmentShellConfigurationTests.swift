import Testing

@testable import AskAgentCore

@Suite("environment.shell (roadmap 0091)")
struct EnvironmentShellConfigurationTests {
    private func parse(_ shell: String, project: Bool = false) throws -> EnvironmentSection? {
        try ConfigurationFile.parse(
            Array(#"{"environment": {"shell": "\#(shell)"}}"#.utf8), path: "c.json", isProject: project
        )
        .environment
    }

    @Test func `a shell name or an absolute path is read, described, and reaches the command policy`() throws {
        #expect(try parse("fish")?.shell == "fish")
        let section = try #require(try parse("/opt/homebrew/bin/fish"))
        #expect(section.description == "shell /opt/homebrew/bin/fish")
        let policy = CommandEnvironment(credentials: [], credentialPrefixes: [], configured: section)
        #expect(policy.shell == "/opt/homebrew/bin/fish")
    }

    @Test func `a later layer's shell replaces an earlier one, and an unset one keeps it`() {
        let base = EnvironmentSection(shell: "bash")
        #expect(base.layered(with: EnvironmentSection(shell: "zsh")).shell == "zsh")
        #expect(base.layered(with: EnvironmentSection()).shell == "bash")
    }

    @Test(arguments: ["powershell", "rm -rf", "relative/sh", ""])
    func `anything else is refused`(_ shell: String) {
        #expect(throws: (any Error).self) { try parse(shell) }
    }

    @Test func `a project's file cannot choose the shell`() {
        #expect(throws: (any Error).self) { try parse("bash", project: true) }
    }
}
