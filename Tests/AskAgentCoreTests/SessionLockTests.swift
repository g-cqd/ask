import AemiIO
import Darwin
import Foundation
import System
import Testing

@testable import AskAgentCore

/// One writer per session. `flock` locks belong to an open file description, so a second descriptor in this
/// process conflicts exactly as a second process would (probed in diary 2026-10-19-10).
@Suite("A session has one writer at a time")
struct SessionLockTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func path(_ name: String) -> FilePath { FilePath(directory.appending(path: name).path) }

    @Test func `an open session cannot be opened again until its owner closes it`() throws {
        do {
            var owner = try SessionFile.create(at: path("s.jsonl"), durability: .none)
            try owner.append(.user("first"))
            #expect(throws: SessionFileError.inUse) { _ = try SessionFile.open(at: path("s.jsonl")) }
        }
        let reopened = try SessionFile.open(at: path("s.jsonl"), durability: .none)
        #expect(reopened.tree.count == 1)
    }

    @Test func `opening holds the lock too, not only creating`() throws {
        do { _ = try SessionFile.create(at: path("s.jsonl"), durability: .none) }
        let owner = try SessionFile.open(at: path("s.jsonl"), durability: .none)
        #expect(throws: SessionFileError.inUse) { _ = try SessionFile.open(at: path("s.jsonl")) }
        _ = owner.tree.count
    }

    @Test func `the session stays locked across the rewrite that repairs a damaged file`() throws {
        let damaged =
            "{\"type\":\"session\",\"version\":1}\n{\"id\":\"a\",\"payload\":{\"kind\":\"user\",\"text\":\"x\"},\"type\":\"entry\"}\n{\"id\":\"b"
        try Data(damaged.utf8).write(to: directory.appending(path: "s.jsonl"))
        var owner = try SessionFile.open(at: path("s.jsonl"), durability: .none)
        #expect(!owner.issues.isEmpty)
        try owner.append(.assistant("after the crash"))
        #expect(FileManager.default.fileExists(atPath: path("s.jsonl.damaged").string))
        #expect(throws: SessionFileError.inUse) { _ = try SessionFile.open(at: path("s.jsonl")) }
    }

    @Test func `a lock on a file that was since replaced is not a lock on the session`() throws {
        try Data("old\n".utf8).write(to: directory.appending(path: "s.jsonl"))
        // Opened before another writer swapped in a new file, and locked after: the old inode is free.
        let stale = try FileDescriptor.open(path("s.jsonl"), .readOnly)
        defer { _ = try? stale.close() }
        try Data("new\n".utf8).write(to: directory.appending(path: "s.tmp"))
        #expect(rename(path("s.tmp").string, path("s.jsonl").string) == 0)
        #expect(try SessionLock.lock(stale, guarding: path("s.jsonl")) == false)
        let current = try FileDescriptor.open(path("s.jsonl"), .readOnly)
        defer { _ = try? current.close() }
        #expect(try SessionLock.lock(current, guarding: path("s.jsonl")))
    }
}
