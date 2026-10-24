import AemiIO
import Darwin
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// Read from `SessionFile` while reviewing `docs/formal/REPORT.md` and then probed here by making one system call fail: a lock taken a
/// moment too soon, a rename that fails after the original was preserved, a flush that fails after the bytes were written (ADR-0084).
@Suite("A session file's failure paths leave nothing open, nothing piled up and nothing undecided")
struct SessionFileFailureTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-session-failure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func path(_ name: String) -> FilePath { FilePath(directory.appending(path: name).path) }
    private func bytes(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appending(path: name)))
    }
    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// Whether this process holds a descriptor open on the file at `path`, by asking the kernel which files its descriptors name.
    private func holdsOpen(_ path: FilePath) -> Bool {
        // The kernel names files by their real path (`/private/var/…`), which Foundation's symlink resolution would shorten.
        var resolved = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard realpath(path.string, &resolved) != nil else { return false }
        let wanted = String(decoding: resolved.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let pid = getpid()
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        var infos = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size)
        let listed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &infos, size)
        for info in infos.prefix(Int(listed) / MemoryLayout<proc_fdinfo>.size)
        where info.proc_fdtype == PROX_FDTYPE_VNODE {
            var vnode = vnode_fdinfowithpath()
            let got = proc_pidfdinfo(
                pid, info.proc_fd, PROC_PIDFDVNODEPATHINFO, &vnode, Int32(MemoryLayout<vnode_fdinfowithpath>.size))
            guard got > 0 else { continue }
            let named = withUnsafeBytes(of: &vnode.pvip.vip_path) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if named == wanted { return true }
        }
        return false
    }

    // MARK: - A lock taken a moment too soon

    @Test func `the check for an open descriptor sees one that is open, and not one that was closed`() throws {
        let target = path("control.jsonl")
        try Data("x".utf8).write(to: URL(fileURLWithPath: target.string))
        let descriptor = try FileDescriptor.open(target, .readOnly)
        #expect(holdsOpen(target))
        try descriptor.close()
        #expect(!holdsOpen(target))
    }

    @Test func `a new session that finds its lock taken does not leave the file it made open`() throws {
        var calls = SessionFileCalls.system
        // What the real adoption does when another process got there first: it closes the descriptor it was given and says so.
        calls.adopt = { descriptor throws(SessionFileError) in
            _ = try? descriptor.close()
            throw .inUse
        }
        let target = path("new.jsonl")
        #expect(throws: SessionFileError.inUse) {
            _ = try SessionFile.begin(SessionTree(), at: target, durability: .none, calls: calls)
        }
        #expect(!holdsOpen(target), "the descriptor `writeExclusively` returned is closed on the way out")
    }

    // MARK: - A rename that fails after the original was kept

    private let damaged = "this is not a record\n"

    @Test func `a rewrite that fails to rename again and again keeps the original once, not once per attempt`() throws {
        try Data(damaged.utf8).write(to: directory.appending(path: "s.jsonl"))
        let failures = Mutex(3)
        var calls = SessionFileCalls.system
        calls.rename = { from, to in
            let fail = failures.withLock { left in
                defer { left -= 1 }
                return left > 0
            }
            if fail {
                errno = EIO
                return -1
            }
            return Darwin.rename(from, to)
        }
        var file = try SessionFile.open(at: path("s.jsonl"), durability: .none, calls: calls)
        for _ in 0 ..< 3 {
            #expect(throws: SessionFileError.io(.rename, errno: EIO)) { try file.append(.user("not yet")) }
        }
        _ = try file.append(.user("at last"))
        let backups = try names().filter { $0.hasPrefix("s.jsonl.damaged") }
        #expect(backups == ["s.jsonl.damaged"], "one copy of the same bytes; found \(backups)")
        #expect(try bytes("s.jsonl.damaged") == Array(damaged.utf8))
        #expect(try SessionLog.decode(bytes("s.jsonl")).entries.count == 1)
    }

    @Test func `a rewrite after the file changed keeps the new original too, whatever was kept before`() throws {
        try Data(damaged.utf8).write(to: directory.appending(path: "s.jsonl"))
        let failures = Mutex(1)
        var calls = SessionFileCalls.system
        calls.rename = { from, to in
            let fail = failures.withLock { left in
                defer { left -= 1 }
                return left > 0
            }
            if fail {
                errno = EIO
                return -1
            }
            return Darwin.rename(from, to)
        }
        var file = try SessionFile.open(at: path("s.jsonl"), durability: .none, calls: calls)
        #expect(throws: SessionFileError.io(.rename, errno: EIO)) { try file.append(.user("not yet")) }
        _ = try file.append(.user("saved"))
        // A second damage, later, is a different file and gets its own copy beside the first.
        try Data("different damage\n".utf8).write(to: directory.appending(path: "s.jsonl"), options: .atomic)
        file = try SessionFile.open(at: path("s.jsonl"), durability: .none)
        _ = try file.append(.user("again"))
        #expect(try names().filter { $0.hasPrefix("s.jsonl.damaged") } == ["s.jsonl.damaged", "s.jsonl.damaged-2"])
    }

    // MARK: - A flush that fails after the bytes were written

    @Test func `a record whose flush failed may be on disk; the next change rewrites from memory and keeps that file`()
        throws
    {
        let first: EntryID
        do {
            var file = try SessionFile.create(at: path("s.jsonl"), durability: .none)
            first = try file.append(.user("one"))
        }
        var calls = SessionFileCalls.system
        let failing = Mutex(true)
        calls.flush = { descriptor, durability throws(SessionFileError) in
            if failing.withLock({ $0 }) { throw .io(.flush, errno: EIO) }
            try SessionFileIO.flush(descriptor, durability)
        }
        var file = try SessionFile.open(at: path("s.jsonl"), durability: .none, calls: calls)
        #expect(throws: SessionFileError.io(.flush, errno: EIO)) { try file.append(.user("flush failed")) }
        #expect(file.tree.entries.map(\.id) == [first], "memory does not hold what was reported as failed")
        let onDisk = try bytes("s.jsonl")
        #expect(
            String(decoding: onDisk, as: UTF8.self).contains("flush failed"),
            "the bytes were written, so they are there")
        failing.withLock { $0 = false }
        let second = try file.append(.user("two"))
        #expect(
            try SessionLog.decode(bytes("s.jsonl")).entries.map(\.id) == [first, second],
            "the live file is memory's again")
        #expect(
            try bytes("s.jsonl.damaged") == onDisk,
            "and the file with the failed record is kept, not discarded (ADR-0013)")
    }
}
