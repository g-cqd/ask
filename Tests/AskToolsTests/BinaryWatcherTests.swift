import Foundation
import Testing

@testable import AskTools

/// The watcher against real files and a real kqueue: no sleeps, every wait ends on an event.
@Suite("A new build appearing beside the running one is reported", .timeLimit(.minutes(1)))
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

    @Test func `a rebuilt executable is reported with its new identity`() async throws {
        let running = try #require(BinaryIdentity(path: path))
        var changes = BinaryWatcher.changes(since: running).makeAsyncIterator()
        try rebuild("build two, longer")
        let reported = await changes.next()
        #expect(reported == BinaryIdentity(path: path))
        #expect(reported != running)
    }

    @Test func `other files changing in the directory report nothing, and the next real build still arrives`()
        async throws
    {
        let running = try #require(BinaryIdentity(path: path))
        var changes = BinaryWatcher.changes(since: running).makeAsyncIterator()
        try Data("noise".utf8).write(to: directory.appending(path: "ask.log"))
        try Data("more noise".utf8).write(to: directory.appending(path: "other"))
        try rebuild("build two")
        // Had the noise been reported, the first value here would equal the running identity.
        let reported = try #require(await changes.next())
        #expect(reported != running)
        #expect(reported == BinaryIdentity(path: path))
    }

    @Test func `a build that landed before the watch began is still reported`() async throws {
        let running = try #require(BinaryIdentity(path: path))
        try rebuild("build two, before anyone watched")
        var changes = BinaryWatcher.changes(since: running).makeAsyncIterator()
        #expect(await changes.next() == BinaryIdentity(path: path))
    }

    @Test func `two builds in a row are two reports, the later one last`() async throws {
        let running = try #require(BinaryIdentity(path: path))
        var changes = BinaryWatcher.changes(since: running).makeAsyncIterator()
        try rebuild("build two")
        let first = try #require(await changes.next())
        try rebuild("build three, longer than the others")
        var latest = first
        while latest != BinaryIdentity(path: path), let next = await changes.next() { latest = next }
        #expect(latest == BinaryIdentity(path: path))
        #expect(latest != first)
    }

    @Test func `cancelling the stream stops the thread and closes what it opened`() async throws {
        let running = try #require(BinaryIdentity(path: path))
        let closed = await withCheckedContinuation { (stopped: CheckedContinuation<(Bool, Bool), Never>) in
            let stream = BinaryWatcher.changes(since: running) { queue, directory in
                stopped.resume(returning: (queue, directory))
            }
            let consumer = Task { for await _ in stream {} }
            consumer.cancel()
        }
        #expect(closed.0, "the kqueue descriptor was open, and is closed")
        #expect(closed.1, "the directory descriptor was open, and is closed")
    }
}
