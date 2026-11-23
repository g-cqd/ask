import Testing

@testable import AskAgentCore

/// `mcp.<server>.sandbox` (security audit 2026-11-22, MED-10): a server a project's file defines runs sandboxed unless the person's
/// own file says otherwise, and that file cannot take it out; the person's own servers run as before unless they ask for it.
@Suite("Which MCP servers run sandboxed")
struct MCPServerSandboxSettingTests {
    private static func servers(_ text: String, isProject: Bool) throws -> [MCPServerSetting] {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: isProject).mcp?.servers ?? []
    }

    @Test func `a project's server is sandboxed, the person's is not unless asked, and either says so`() throws {
        let entry = #"{"mcp":{"s":{"command":"srv"}}}"#
        let project = try #require(try Self.servers(entry, isProject: true).first)
        #expect(project.definedByProject && project.isSandboxed)
        let own = try #require(try Self.servers(entry, isProject: false).first)
        #expect(!own.definedByProject && !own.isSandboxed)
        let asked = try #require(
            try Self.servers(#"{"mcp":{"s":{"command":"srv","sandbox":true}}}"#, isProject: false).first
        )
        #expect(asked.isSandboxed)
        #expect(MCPSection(servers: [project]).description == "s (command, sandboxed)")
        #expect(MCPSection(servers: [own]).description == "s (command)")
    }

    @Test func `a project's file cannot take a server out of the sandbox, nor change the person's server's`() {
        #expect(throws: ConfigurationError.self) {
            _ = try Self.servers(#"{"mcp":{"s":{"command":"srv","sandbox":false}}}"#, isProject: true)
        }
        #expect(throws: ConfigurationError.self, "a change to a lower file's server may not touch its sandbox") {
            _ = try Self.servers(#"{"mcp":{"s":{"sandbox":false}}}"#, isProject: true)
        }
    }

    @Test func `a project's server of the same name replaces the person's whole, sandboxed`() throws {
        let project = try Self.servers(#"{"mcp":{"s":{"command":"theirs"}}}"#, isProject: true)
        let own = try Self.servers(#"{"mcp":{"s":{"command":"mine","sandbox":false}}}"#, isProject: false)
        let layered = MCPSection(servers: own).layered(with: MCPSection(servers: project))
        #expect(
            layered.servers.first?.command == "theirs" && layered.servers.first?.isSandboxed == true,
            "the higher file wins whole"
        )
    }
}
