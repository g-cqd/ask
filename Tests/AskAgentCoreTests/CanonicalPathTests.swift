import Darwin
import Foundation
import Testing

@testable import AskAgentCore

/// Canonical paths against a real file system: the same file reached by symlink, by `..`, by a dangling link or by
/// a different spelling of its name must come out as one path, or a rule about it has a hole.
@Suite("Every way to reach a file canonicalizes to one path")
struct CanonicalPathTests {
    private let root: String

    init() throws {
        let made = FileManager.default.temporaryDirectory.appending(path: "ask-canon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: made.appending(path: "real/inner"), withIntermediateDirectories: true)
        root = String(cString: realpath(made.path, nil))  // /var is a symlink to /private/var
    }

    private func link(_ name: String, to target: String) throws {
        try FileManager.default.createSymbolicLink(atPath: root + "/" + name, withDestinationPath: target)
    }

    private func canonical(_ path: String, from directory: String? = nil) -> String? {
        CanonicalPath.of(path, relativeTo: directory ?? root)
    }

    @Test func `an existing path is its real path, relative or absolute, with dots resolved`() {
        #expect(canonical("real/inner") == root + "/real/inner")
        #expect(canonical(root + "/real/./inner/../inner") == root + "/real/inner")
        #expect(canonical("inner", from: root + "/real") == root + "/real/inner")
        #expect(canonical("real/inner/") == root + "/real/inner")
        #expect(canonical("/") == "/")
    }

    @Test func `a symbolic link is followed, and dot-dot after one is the target's parent, as the kernel does`() throws
    {
        try link("alias", to: root + "/real/inner")
        #expect(canonical("alias") == root + "/real/inner")
        #expect(canonical("alias/..") == root + "/real")
        #expect(canonical("alias/../inner") == root + "/real/inner")
    }

    @Test func `a path that does not exist yet is its deepest existing directory plus the new names`() {
        #expect(canonical("real/new.txt") == root + "/real/new.txt")
        #expect(canonical("real/a/b/c.txt") == root + "/real/a/b/c.txt")
        #expect(canonical("real/./a//b") == root + "/real/a/b")
    }

    @Test func `dot-dot after a name that does not exist is refused, since the kernel would fail it`() {
        #expect(canonical("real/missing/../inner/file") == nil)
        #expect(canonical("missing/..") == nil)
    }

    @Test func `a dangling link is followed to where writing through it would create the file`() throws {
        try link("dangling", to: root + "/real/inner/created.txt")
        #expect(canonical("dangling") == root + "/real/inner/created.txt")
        try link("relative", to: "real/inner/also-created")
        #expect(canonical("relative") == root + "/real/inner/also-created")
        try link("chain", to: root + "/dangling")
        #expect(canonical("chain") == root + "/real/inner/created.txt")
        try link("through", to: root + "/real/not-yet-a-dir")
        #expect(canonical("through/x/y") == root + "/real/not-yet-a-dir/x/y")
    }

    @Test func `a link loop cannot be resolved`() throws {
        try link("one", to: root + "/two")
        try link("two", to: root + "/one")
        #expect(canonical("one") == nil)
        #expect(canonical("one/inner") == nil)
    }

    @Test func `a chain of dangling links longer than the kernel follows cannot be resolved`() throws {
        try link("end", to: root + "/real/never-created")
        var previous = "end"
        for number in 1 ... 40 {
            try link("hop\(number)", to: root + "/" + previous)
            previous = "hop\(number)"
        }
        #expect(canonical("hop3") == root + "/real/never-created")
        #expect(canonical("hop40") == nil)
    }

    @Test func `a NUL byte cannot be part of a path`() {
        #expect(canonical("real/in\0ner") == nil)
        #expect(CanonicalPath.of("x", relativeTo: root + "\0") == nil)
    }

    @Test func `names with spaces and non-ASCII letters survive`() throws {
        try FileManager.default.createDirectory(atPath: root + "/dossier été", withIntermediateDirectories: true)
        #expect(canonical("dossier été/fichier 1.txt") == root + "/dossier été/fichier 1.txt")
    }

    /// The default volume ignores case. On one that does not, this test has nothing to say.
    @Test(.enabled(if: CanonicalPathTests.volumeIgnoresCase()))
    func `a differently cased spelling is the file's real spelling`() {
        #expect(canonical("REAL/INNER") == root + "/real/inner")
        #expect(canonical("Real/Inner/new.txt") == root + "/real/inner/new.txt")
    }

    private static func volumeIgnoresCase() -> Bool {
        let probe = FileManager.default.temporaryDirectory.appending(path: "AskCase\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: probe) }
        try? FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        return FileManager.default.fileExists(atPath: probe.path.lowercased())
    }
}
