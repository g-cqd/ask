import Foundation
import Testing

@testable import AskTools

/// The identity check against real files; the watching itself is `FileChangeSignal`'s and AemiIO's.
@Suite("A new build appearing beside the running one is reported once")
struct BinaryWatcherTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("build one".utf8).write(to: directory.appending(path: "ask"))
    }

    private var path: String { directory.appending(path: "ask").path }

    /// What a linker does: write the new file beside the old one, then swap it in.
    private func rebuild(_ text: String) throws {
        let staged = directory.appending(path: "ask.new-\(UUID().uuidString)")
        try Data(text.utf8).write(to: staged)
        _ = try FileManager.default.replaceItemAt(URL(filePath: path), withItemAt: staged)
    }

    @Test func `a rebuilt executable is reported with its new identity, once`() throws {
        let running = try #require(BinaryIdentity(path: path))
        var watcher = BinaryWatcher(since: running)
        #expect(watcher.look() == nil, "nothing new yet")
        try rebuild("build two, longer")
        let look = watcher.look()
        let reported = try #require(look)
        #expect(reported == BinaryIdentity(path: path))
        #expect(reported != running)
        #expect(watcher.look() == nil, "the same build is not reported twice")
    }

    @Test func `other files changing in the directory report nothing`() throws {
        let running = try #require(BinaryIdentity(path: path))
        var watcher = BinaryWatcher(since: running)
        try Data("noise".utf8).write(to: directory.appending(path: "ask.log"))
        #expect(watcher.look() == nil)
    }

    @Test func `two builds in a row are two reports, the later one last`() throws {
        let running = try #require(BinaryIdentity(path: path))
        var watcher = BinaryWatcher(since: running)
        try rebuild("build two")
        let firstLook = watcher.look()
        let first = try #require(firstLook)
        try rebuild("build three, longer than the others")
        let secondLook = watcher.look()
        let second = try #require(secondLook)
        #expect(second != first)
        #expect(second == BinaryIdentity(path: path))
    }
}
