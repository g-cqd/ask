import Testing

@testable import AskAgentCore

/// A preset names a set of servers ask knows (the owner's choice, 2026-11-02, roadmap 0190): `"presets": ["swift"]` connects apple-docs
/// and swift-search, as if the file named them, so a project's file goes through the same trust as its own servers.
@Suite("A preset adds the servers it names to the file that names it, and a server the file names itself wins")
struct MCPPresetTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    @Test func `swift adds apple-docs over HTTP and swift-search from the PATH`() throws {
        let file = try parse(#"{"presets":["swift"]}"#)
        let servers = try #require(file.mcp?.servers)
        #expect(servers.map(\.name) == ["apple-docs", "swift-search"])
        #expect(servers[0] == MCPServerSetting(name: "apple-docs", url: "https://apple-docs-mcp.everest.mt/mcp"))
        #expect(servers[1] == MCPServerSetting(name: "swift-search", command: "swift-search", args: ["mcp"]))
        #expect(file.presets == ["swift"])
    }

    @Test func `a server the file names itself replaces the preset's, and the others stay`() throws {
        let file = try parse(
            #"{"presets":["swift"],"mcp":{"swift-search":{"command":"/opt/ss","args":["mcp"]},"x":{"url":"https://x.test"}}}"#
        )
        let servers = try #require(file.mcp?.servers)
        #expect(servers.map(\.name) == ["apple-docs", "swift-search", "x"])
        #expect(servers[1].command == "/opt/ss")
    }

    @Test func `a change in the same file, such as enabled false, applies to the preset's server`() throws {
        let file = try parse(
            #"{"presets":["swift"],"mcp":{"apple-docs":{"enabled":false},"other":{"enabled":false}}}"#,
            project: true
        )
        let servers = try #require(file.mcp?.servers)
        #expect(servers.first { $0.name == "apple-docs" }?.enabled == false)
        #expect(servers.first { $0.name == "swift-search" }?.enabled == true)
        #expect(file.mcp?.masks.map(\.name) == ["other"], "a change to no preset's server is left for a lower file")
    }

    @Test func `an unknown preset is refused with the ones there are`() {
        #expect(throws: ConfigurationError.self) { try parse(#"{"presets":["rust"]}"#) }
        do {
            _ = try parse(#"{"presets":["rust"]}"#)
        } catch {
            guard case .outOfRange(_, let key, let reason) = error else {
                Issue.record("\(error)")
                return
            }
            #expect(key == "presets" && reason.contains("rust") && reason.contains("swift"))
        }
    }

    @Test func `a project's file may name a preset, as it may name servers`() throws {
        let file = try parse(#"{"presets":["swift"]}"#, project: true)
        #expect(file.mcp?.servers.count == 2)
    }

    @Test func `no presets, no servers added`() throws {
        #expect(try parse("{}").mcp == nil)
        #expect(try parse(#"{"presets":[]}"#).mcp == nil)
    }
}
