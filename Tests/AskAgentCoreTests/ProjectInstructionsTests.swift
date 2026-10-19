import Foundation
import Testing

@testable import AskAgentCore

/// Instruction files projects carry for agents, found from the working directory up to the home directory.
@Suite("Project instructions are found outermost first, nearer files last")
struct ProjectInstructionsTests {
    private let home: URL
    private let config: URL

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-instr-\(UUID().uuidString)")
        home = URL(fileURLWithPath: (root.path as NSString).resolvingSymlinksInPath).appending(path: "home")
        config = home.appending(path: ".config/ask")
        try FileManager.default.createDirectory(
            at: home.appending(path: "code/app/sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    }

    private func write(_ relative: String, _ text: String, under base: URL? = nil) throws {
        try Data(text.utf8).write(to: (base ?? home).appending(path: relative))
    }

    private func discover(from relative: String) -> [ProjectInstructions.File] {
        ProjectInstructions.discover(
            from: home.appending(path: relative).path, home: home.path, configDirectory: config.path)
    }

    @Test func `files are collected from home down to the working directory, global first`() throws {
        try write("AGENTS.md", "global", under: config)
        try write("AGENTS.md", "home")
        try write("code/app/AGENTS.md", "app")
        try write("code/app/sub/AGENTS.md", "sub")
        let found = discover(from: "code/app/sub")
        #expect(found.map(\.text) == ["global", "home", "app", "sub"])
        #expect(found.last?.path == home.appending(path: "code/app/sub/AGENTS.md").path)
    }

    @Test func `AGENTS.md wins over CLAUDE.md in the same directory, and CLAUDE.md stands alone`() throws {
        try write("code/app/AGENTS.md", "agents")
        try write("code/app/CLAUDE.md", "claude")
        try write("code/CLAUDE.md", "only claude")
        #expect(discover(from: "code/app").map(\.text) == ["only claude", "agents"])
    }

    @Test func `nothing above the home directory is read`() throws {
        try Data("outside".utf8).write(to: home.deletingLastPathComponent().appending(path: "AGENTS.md"))
        try write("code/AGENTS.md", "inside")
        #expect(discover(from: "code/app").map(\.text) == ["inside"])
    }

    @Test func `outside the home directory, only the working directory itself is read`() throws {
        let elsewhere = home.deletingLastPathComponent().appending(path: "elsewhere/deep")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("parent".utf8).write(to: elsewhere.deletingLastPathComponent().appending(path: "AGENTS.md"))
        try Data("here".utf8).write(to: elsewhere.appending(path: "AGENTS.md"))
        let found = ProjectInstructions.discover(from: elsewhere.path, home: home.path, configDirectory: config.path)
        #expect(found.map(\.text) == ["here"])
    }

    @Test func `a large file is truncated and says so; a binary file is skipped with a reason`() throws {
        try write("code/AGENTS.md", String(repeating: "x", count: ProjectInstructions.maximumBytes + 10))
        try Data([0x00, 0x01, 0xFF]).write(to: home.appending(path: "code/app/AGENTS.md"))
        let found = discover(from: "code/app")
        #expect(found.count == 2)
        #expect(found[0].text.hasSuffix(ProjectInstructions.truncationNote))
        #expect(
            found[0].text.utf8.count <= ProjectInstructions.maximumBytes + ProjectInstructions.truncationNote.utf8.count
        )
        #expect(found[1].text.isEmpty && found[1].skippedBecause != nil)
    }

    @Test func `the prompt blocks name each file`() throws {
        try write("code/AGENTS.md", "Use tabs.")
        let blocks = ProjectInstructions.promptBlocks(discover(from: "code"))
        #expect(blocks == ["Instructions from \(home.appending(path: "code/AGENTS.md").path):\n\nUse tabs."])
    }
}
