import Foundation
import Testing

@testable import AskAgentCore

/// A later file changes a server a lower one defines, rather than replacing it (roadmap 0127): an entry with no `command` and no `url`
/// masks the same-named server, and may change only what is used of it (`enabled`, `tools`, `mode`, `maxDirectTools`), never what runs or
/// what it is given, so a project cannot point your server, and the secrets you gave it, at a program of its own.
@Suite("A project's file can change one of your MCP servers without replacing it")
struct MCPServerMaskTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "ask-mcp-mask-\(UUID().uuidString)")

    private func write(_ path: String, _ text: String) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: URL(filePath: path))
    }

    private func loaded(user: String, project: String) throws -> ConfigurationLoader.Result {
        let loader = ConfigurationLoader(
            project: root.path + "/project", configDirectory: root.path + "/config", environment: [:])
        try write(loader.userPath, user)
        try write(loader.projectPath, project)
        var trust = ProjectTrust()
        trust.trust(loader.projectPath, bytes: Array(project.utf8))
        try trust.save(to: loader.trustPath)
        defer { try? FileManager.default.removeItem(at: root) }
        return try loader.load()
    }

    private static let user =
        #"{mcp: {xcode: {command: "xcrun", args: ["mcpbridge"]}, docs: {url: "https://d.example/mcp"}}}"#

    @Test func `turning one of your servers off keeps the others and its definition`() throws {
        let result = try loaded(user: Self.user, project: #"{mcp: {xcode: {enabled: false}}}"#)
        let servers = result.configuration.mcp.value.servers
        #expect(servers.map(\.name) == ["docs", "xcode"])
        let xcode = try #require(servers.first { $0.name == "xcode" })
        #expect(!xcode.enabled && xcode.command == "xcrun" && xcode.args == ["mcpbridge"])
        #expect(servers.first { $0.name == "docs" }?.enabled == true)
    }

    @Test func `a mask changes only what it sets`() throws {
        let user = #"{mcp: {xcode: {command: "xcrun", enabled: false, mode: "search"}}}"#
        let result = try loaded(user: user, project: #"{mcp: {xcode: {tools: ["build"]}}}"#)
        let xcode = try #require(result.configuration.mcp.value.servers.first)
        #expect(xcode.tools == ["build"] && !xcode.enabled && xcode.mode == .search)
    }

    @Test func `a mask naming no server of yours is ignored, and said`() throws {
        let result = try loaded(user: Self.user, project: #"{mcp: {lldb: {enabled: false}}}"#)
        #expect(result.configuration.mcp.value.servers.map(\.name) == ["docs", "xcode"])
        #expect(result.notices.contains { $0.contains("\"mcp.lldb\"") && $0.contains("ignored") })
    }

    @Test(arguments: [
        #"{mcp: {xcode: {args: ["--evil"]}}}"#, #"{mcp: {xcode: {env: {A: "b"}}}}"#,
        #"{mcp: {xcode: {cwd: "/tmp"}}}"#, #"{mcp: {xcode: {headers: {A: "b"}}}}"#
    ])
    func `a mask cannot change what runs or what it is given`(project: String) {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationFile.parse(Array(project.utf8), path: "p.json", isProject: true)
        }
    }

    @Test func `in your own file, the lowest layer, an entry still needs a command or a url`() {
        #expect(throws: ConfigurationError.self) {
            try ConfigurationFile.parse(Array(#"{mcp: {xcode: {enabled: false}}}"#.utf8), path: "u.json")
        }
    }

    @Test func `trusting a file that masks says what it changes`() throws {
        let file = try ConfigurationFile.parse(
            Array(#"{mcp: {xcode: {enabled: false, tools: ["build"]}}}"#.utf8), path: "p.json", isProject: true)
        #expect(file.mcp?.consent == ["xcode: changes your server: off, tools build"])
    }
}
