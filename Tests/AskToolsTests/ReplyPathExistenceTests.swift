internal import AskAgentCore
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskTools

/// n33 / roadmap 0215: reply rendering may not stat protected files or follow a link outside the workspace.
@Suite("Reply path existence is confined to readable workspace entries")
struct ReplyPathExistenceTests {
    private let checker = ReplyPathExistence()
    @Test func `existing readable files and folders are found but denied paths are not`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "reply-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appending(path: "folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(checker.exists(folder.path, in: root.path, policy: .unrestricted))
        let file = root.appending(path: "a.txt")
        try Data("a".utf8).write(to: file)
        #expect(checker.exists(file.path, in: root.path, policy: .unrestricted))
        let deny = SandboxPolicy(denyRead: [SandboxRule(CanonicalPath.of(root.path, relativeTo: "/")!, .subpath)])
        #expect(!checker.exists(file.path, in: root.path, policy: deny))
        #expect(
            checker.exists(file.path, in: root.path, policy: .unrestricted),
            "policy changes invalidate cached answers"
        )
        #expect(
            !checker.exists(root.appending(path: "missing.txt").path, in: root.path, policy: .unrestricted)
        )
    }

    @Test func `neither a directory link nor a leaf link is followed even when its target exists`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "reply-links-\(UUID().uuidString)")
        let workspace = root.appending(path: "work")
        let outside = root.appending(path: "outside")
        for directory in [workspace, outside] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let target = outside.appending(path: "secret.txt")
        try Data("secret".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: workspace.appending(path: "dir"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(
            at: workspace.appending(path: "leaf.txt"),
            withDestinationURL: target
        )
        for path in [
            workspace.appending(path: "dir/secret.txt").path, workspace.appending(path: "leaf.txt").path, target.path
        ] {
            #expect(!checker.exists(path, in: workspace.path, policy: .unrestricted))
        }
        for path in ["", "a.txt", workspace.path + "/../outside/secret.txt", workspace.path + "/a\0.txt"] {
            #expect(!checker.exists(path, in: workspace.path, policy: .unrestricted))
        }
    }

    /// The review of 2026-11-11: "not there" was kept for the whole conversation, so a file the model made after first naming it
    /// was never linked.
    @Test func `a file made after it was first looked for is found once the answer has aged, and not before`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "reply-new-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = ContinuousClock.now
        let elapsed = Mutex(Duration.zero)
        let checker = ReplyPathExistence(now: { start + elapsed.withLock { $0 } })
        let file = root.appending(path: "new.txt")
        #expect(!checker.exists(file.path, in: root.path, policy: .unrestricted))
        try Data("x".utf8).write(to: file)
        elapsed.withLock { $0 = .seconds(1) }
        #expect(
            !checker.exists(file.path, in: root.path, policy: .unrestricted),
            "within its age the answer is kept, not looked up again"
        )
        elapsed.withLock { $0 = .seconds(3) }
        #expect(checker.exists(file.path, in: root.path, policy: .unrestricted))
        try FileManager.default.removeItem(at: file)
        elapsed.withLock { $0 = .seconds(60) }
        #expect(
            checker.exists(file.path, in: root.path, policy: .unrestricted),
            "a file found stays found: a click says when it is gone"
        )
    }
}
