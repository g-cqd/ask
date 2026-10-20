internal import Foundation
internal import System
internal import Testing

@testable import AskAgentCore

struct SessionFormatUpgradeTests {
    private let legacy = Array(
        "{\"type\":\"session\",\"version\":1}\n{\"type\":\"entry\",\"id\":\"0\",\"payload\":{\"kind\":\"user\",\"text\":\"legacy history\"}}\n{\"type\":\"leaf\",\"id\":\"0\"}\n"
            .utf8)

    @Test func `new snapshots carry version two so older readers cannot discard routing protection`() throws {
        #expect(SessionLog.formatVersion == 2)
        let bytes = try SessionLog.snapshot(SessionTree())
        #expect(String(decoding: bytes, as: UTF8.self).contains(#""version":2"#))
    }

    @Test func `legacy history still decodes without pretending it had an account binding`() throws {
        let tree = try SessionLog.decode(legacy)
        #expect(tree.destination == nil)
        #expect(SessionSummary(tree).firstPrompt == "legacy history")
    }

    @Test func `opening legacy bytes is read only and the first change preserves and upgrades them`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appending(path: "session.jsonl")
        try Data(legacy).write(to: path)
        var file = try SessionFile.open(at: FilePath(path.path))
        #expect(file.formatVersion == 1)
        #expect(file.issues.isEmpty, "an upgrade is not a damage repair")
        #expect(try Data(contentsOf: path) == Data(legacy))
        #expect(!FileManager.default.fileExists(atPath: path.path + ".version-1"))
        let route = SessionDestination(
            connectionID: "stable", authorizationID: "revision", name: "work", model: "model")
        try file.append(.destination(route))
        #expect(file.formatVersion == 2)
        let written = try Data(contentsOf: path)
        #expect(String(decoding: written, as: UTF8.self).contains(#""version":2"#))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path.path + ".version-1")) == Data(legacy))
        #expect(try SessionLog.decode(Array(written)).destination == route)
        #expect(try SessionLog.decode(Array(written)).entries.count == 2)
    }
}
