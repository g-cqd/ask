import Foundation
import Testing

@testable import AskTools

/// What counts as a new build: a replaced file, or one rewritten in place, and nothing else.
@Suite("A rebuilt executable has a different identity from the one that is running")
struct BinaryIdentityTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var path: String { directory.appending(path: "ask").path }

    private func write(_ text: String, to name: String = "ask") throws {
        try Data(text.utf8).write(to: directory.appending(path: name))
    }

    @Test func `the same file is the same build, however often it is examined`() throws {
        try write("one")
        #expect(BinaryIdentity(path: path) == BinaryIdentity(path: path))
        #expect(BinaryIdentity(path: path) != nil)
    }

    @Test func `a file replaced by a rename is a new build, as a linker replaces one`() throws {
        try write("one")
        let before = try #require(BinaryIdentity(path: path))
        try write("one", to: "next")
        _ = try FileManager.default.replaceItemAt(URL(filePath: path), withItemAt: directory.appending(path: "next"))
        let after = try #require(BinaryIdentity(path: path))
        #expect(after != before)
    }

    @Test func `a file rewritten in place with other content is a new build`() throws {
        try write("one")
        let before = try #require(BinaryIdentity(path: path))
        try write("one, and more")
        #expect(try #require(BinaryIdentity(path: path)) != before)
    }

    @Test func `a symlink is followed to the real file, so the build directory's alias changes nothing`() throws {
        try write("one")
        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "alias"), withDestinationURL: directory.appending(path: "ask"))
        let viaAlias = try #require(BinaryIdentity(path: directory.appending(path: "alias").path))
        let direct = try #require(BinaryIdentity(path: path))
        #expect(viaAlias == direct)
        #expect(viaAlias.path.hasSuffix("/ask"))
    }

    @Test func `a missing file has no identity, and the running executable does`() {
        #expect(BinaryIdentity(path: directory.appending(path: "absent").path) == nil)
        #expect(BinaryIdentity.running() != nil)
    }

    @Test func `the summary says when it was built and how large it is`() throws {
        try write(String(repeating: "x", count: 2_500_000))
        let summary = try #require(BinaryIdentity(path: path)).summary
        #expect(summary.hasPrefix("built ") && summary.hasSuffix(", 2.5 MB"))
    }
}
