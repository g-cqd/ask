internal import Darwin
internal import Foundation
internal import Synchronization
internal import Testing

@testable import AskAI

/// Replacing a file by renaming a new one over it is crash-safe only if the new bytes reach the disk before the rename, and the rename
/// before the caller is told (roadmap 0060, ADR-0089). Found by `fcheck` (`replace-not-durable`): the file was flushed with `fsync`,
/// which on macOS does not make the drive order its writes, and the directory was not flushed at all.
@Suite("A replaced file is made durable before the rename, and its directory after it")
struct AtomicFileDurabilityTests {
    /// The flushes a test saw, in order.
    private final class Events: Sendable {
        private let log = Mutex<[String]>([])
        func add(_ event: String) { log.withLock { $0.append(event) } }
        var all: [String] { log.withLock { $0 } }
    }

    private let directory: URL
    private var target: URL { directory.appending(path: "target.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-atomic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// A flush that records what it was asked to flush and what the target held at that moment.
    private func recording(_ events: Events, failing: String? = nil) -> (Int32) -> Int32 {
        let target = target
        return { descriptor in
            var info = stat()
            fstat(descriptor, &info)
            let kind = info.st_mode & S_IFMT == S_IFDIR ? "directory" : "file"
            let held = (try? String(contentsOf: target, encoding: .utf8)) ?? "absent"
            events.add("\(kind) while \(held)")
            if kind == failing {
                errno = EIO
                return -1
            }
            return 0
        }
    }

    @Test func `the new bytes are flushed while the old file is still there, and the directory once the new one is`()
        throws
    {
        try Data("old".utf8).write(to: target)
        let events = Events()
        try AtomicFile.replace(target, with: Array("new".utf8), flush: recording(events))
        #expect(events.all == ["file while old", "directory while new"])
        #expect(try String(contentsOf: target, encoding: .utf8) == "new")
    }

    @Test func `a file that did not exist is flushed the same way`() throws {
        let events = Events()
        try AtomicFile.replace(target, with: Array("new".utf8), flush: recording(events))
        #expect(events.all == ["file while absent", "directory while new"])
    }

    @Test func `when the new bytes cannot be flushed the old file stays and no temporary file is left`() throws {
        try Data("old".utf8).write(to: target)
        let events = Events()
        #expect(throws: AtomicFile.Failure(code: EIO)) {
            try AtomicFile.replace(target, with: Array("new".utf8), flush: recording(events, failing: "file"))
        }
        #expect(try String(contentsOf: target, encoding: .utf8) == "old")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["target.json"])
    }

    @Test func `when the directory cannot be flushed the caller is told`() throws {
        try Data("old".utf8).write(to: target)
        let events = Events()
        #expect(throws: AtomicFile.Failure(code: EIO)) {
            try AtomicFile.replace(target, with: Array("new".utf8), flush: recording(events, failing: "directory"))
        }
    }

    @Test func `the barrier flush succeeds on a file and on a directory, and fails on a descriptor that is not open`()
        throws
    {
        try Data("x".utf8).write(to: target)
        let file = open(target.path, O_RDONLY)
        let folder = open(directory.path, O_RDONLY | O_DIRECTORY)
        defer {
            close(file)
            close(folder)
        }
        #expect(FileFlush.barrier(file) == 0 && FileFlush.barrier(folder) == 0)
        #expect(FileFlush.barrier(-1) == -1 && errno == EBADF)
    }
}
