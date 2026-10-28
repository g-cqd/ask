internal import Darwin
internal import Foundation
internal import Testing

@testable import AskAgentCore

@Suite("Two ask processes changing one settings file cannot erase each other's change")
struct ConfigEditorLockTests {
    private func makeFile() throws -> String {
        let directory = NSTemporaryDirectory() + "ask-lock-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let path = directory + "/config.json"
        try "{}".write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test func `simultaneous changes to different settings all survive`() async throws {
        let path = try makeFile()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let changes: [(String, [String])] = [
            ("on", ["ui", "tint"]), ("none", ["sandbox", "network"]), ("closed", ["ui", "sidebar"]),
            ("high", ["thinking"])
        ]
        // Editors opened before any commit hold the same stale copy, as two processes do.
        let editors = try changes.map { _ in try ConfigEditor(path: path, isProject: false) }
        await withTaskGroup(of: Void.self) { group in
            for (editor, change) in zip(editors, changes) {
                group.addTask { try? editor.commit(change.0, at: change.1) }
            }
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        for word in ["tint", "network", "sidebar", "thinking"] { #expect(text.contains(word), "\(word) lost: \(text)") }
    }

    @Test func `a lock another process holds makes a change fail, and nothing is written`() throws {
        let path = try makeFile()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        let descriptor = open((path as NSString).deletingLastPathComponent, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        #expect(descriptor >= 0 && flock(descriptor, LOCK_EX) == 0)
        defer { close(descriptor) }
        let editor = try ConfigEditor(path: path, isProject: false)
        #expect(throws: ConfigEditor.Error.self) { try editor.commit("on", at: ["thinking"]) }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "{}")
    }
}
