internal import Foundation
internal import Testing

@testable import AskAgentCore

/// Session directories are the person's alone (roadmap 0153, hardening): their names say which projects were worked on, and the files
/// in them the conversations. Created 0700, and an older one made with the default 0755 is tightened.
@Suite("Session directories only their owner can open")
struct SessionDirectoryPermissionsTests {
    private func mode(_ path: String) throws -> Int {
        try #require(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber).intValue
    }

    @Test func `a new directory, and the ones above it that ask owns, are 0700`() throws {
        let state = NSTemporaryDirectory() + "ask-perm-" + UUID().uuidString
        let directory = SessionDirectory(project: "/Users/g/work", environment: ["XDG_STATE_HOME": state])
        try directory.create()
        #expect(try mode(directory.path) == 0o700)
        #expect(try mode(state + "/ask/sessions") == 0o700 && mode(state + "/ask") == 0o700)
    }

    @Test func `a directory made before with 0755 is tightened`() throws {
        let state = NSTemporaryDirectory() + "ask-perm-" + UUID().uuidString
        let directory = SessionDirectory(project: "/Users/g/work", environment: ["XDG_STATE_HOME": state])
        try FileManager.default.createDirectory(
            atPath: directory.path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try directory.create()
        #expect(try mode(directory.path) == 0o700 && mode(state + "/ask") == 0o700)
    }
}
