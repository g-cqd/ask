internal import Foundation
internal import Testing

@testable import AskTUI

/// Rendering by itself has no filesystem authority; only the conversation may supply a policy-aware reply-path lookup.
@Suite("A screen without a path policy never stats reply references")
struct ReplyPathPolicyTests {
    @Test func `an existing relative file is not linked by the default screen lookup`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "screen-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("a".utf8).write(to: root.appending(path: "a.txt"))
        var options = ScreenOptions()
        options.workspace = root.path
        let state = ScreenState(label: "m", options: options)
        let paths = try #require(state.blocks.paths)
        #expect(paths.paths(in: "a.txt").isEmpty)
        var supplied = paths
        supplied.exists = { $0 == root.path + "/a.txt" }
        #expect(supplied.paths(in: "a.txt").count == 1)
    }
}
