import AemiIO
import Darwin
import Foundation
import System
import Testing

@testable import AskAgentCore

/// A session remembers the strict sandbox it ran under, in a record outside the entry chain, so resuming it keeps
/// that sandbox. An older ask that cannot read the record skips one line; no entry is orphaned.
@Suite("A session records its strict sandbox outside the conversation, and keeps it")
struct SessionSandboxRecordTests {
    private let strict = SandboxSection(write: [.workspace, .paths(["/a"])], network: SandboxPolicy.Network.none)

    @Test func `the record's bytes are pinned, outside the entry chain`() throws {
        let line = try SessionLog.line(forSandbox: strict)
        #expect(
            String(decoding: line, as: UTF8.self)
                == #"{"network":"none","type":"sandbox","write":["workspace",["/a"]]}"# + "\n")
    }

    @Test func `a snapshot carries it, and the latest record wins on replay`() throws {
        var tree = SessionTree()
        try tree.append(.user("hi"))
        tree.recordSandbox(SandboxSection(network: .localhost))
        tree.recordSandbox(strict)
        let decoded = try SessionLog.decode(try SessionLog.snapshot(tree))
        #expect(decoded.sandbox == strict)
        #expect(decoded.entries == tree.entries)
        let appended = try SessionLog.snapshot(tree) + SessionLog.line(forSandbox: SandboxSection(network: .any))
        #expect(try SessionLog.decode(appended).sandbox == SandboxSection(network: .any))
    }

    @Test func `a session that never recorded one has none`() throws {
        var tree = SessionTree()
        try tree.append(.user("hi"))
        #expect(try SessionLog.decode(try SessionLog.snapshot(tree)).sandbox == nil)
    }

    @Test func `a record written between entries does not break the chain`() throws {
        var tree = SessionTree()
        let first = try tree.append(.user("one"))
        let header = try SessionLog.snapshot(SessionTree())
        let bytes = header + (try SessionLog.line(for: tree.entries[0])) + (try SessionLog.line(forSandbox: strict))
        var next = tree
        try next.append(.assistant("two"))
        let all = bytes + (try SessionLog.line(for: next.entries[1]))
        let recovered = try SessionLog.recover(all)
        #expect(recovered.issues.isEmpty)
        #expect(recovered.tree.entries.map(\.parentID) == [nil, first])
        #expect(recovered.tree.sandbox == strict)
    }

    @Test func `a reader that cannot parse a record skips that line only`() throws {
        var tree = SessionTree()
        try tree.append(.user("one"))
        try tree.append(.assistant("two"))
        var bytes = try SessionLog.snapshot(SessionTree())
        bytes += try SessionLog.line(for: tree.entries[0])
        bytes += Array(#"{"type":"from-the-future","x":1}"#.utf8) + [0x0A]
        bytes += try SessionLog.line(for: tree.entries[1])
        let recovered = try SessionLog.recover(bytes)
        #expect(
            recovered.issues == [.malformedLine(line: 4)], "the header and an empty snapshot's leaf are lines 1 and 2")
        #expect(recovered.tree.entries == tree.entries, "nothing orphaned")
    }

    @Test func `resuming narrows the configuration by the session's record, except where a flag spoke`() {
        let files = Configuration.defaults.applying(
            ConfigurationFile(sandbox: SandboxSection(network: .localhost)), from: .file("/u"))
        let resumed = files.applying(session: strict, flaggedNetwork: false, flaggedWrite: false, flaggedRead: false)
        #expect(resumed.sandbox.value.network == SandboxPolicy.Network.none)
        #expect(resumed.sandbox.value.write == strict.write)
        #expect(resumed.sandbox.source == .session)
        let flagged = files.applying(session: strict, flaggedNetwork: true, flaggedWrite: true, flaggedRead: true)
        #expect(flagged == files, "a flag is the user widening; the record does not override it")
        let wider = files.applying(
            session: SandboxSection(network: .any), flaggedNetwork: false, flaggedWrite: false, flaggedRead: false)
        #expect(wider == files, "a record never widens the files either")
        #expect(Configuration.Source.session.description == "this session's record")
        let again = resumed.applying(
            session: resumed.sandbox.value, flaggedNetwork: false, flaggedWrite: false, flaggedRead: false)
        #expect(again.sandbox.value.write == strict.write, "resuming its own record does not grow it")
    }

    /// Writing defaults to the workspace (owner, 2026-10-29), so `anywhere` in a record would widen: a session file can come from anywhere
    /// (`--session PATH`), and one run once with `--write anywhere` would keep it after the flag is gone.
    @Test func `a record of write or read anywhere does not widen the default workspace`() {
        let files = Configuration.defaults
        let record = SandboxSection(write: [.anywhere], read: [.anywhere])
        let resumed = files.applying(session: record, flaggedNetwork: false, flaggedWrite: false, flaggedRead: false)
        #expect(resumed == files)
        #expect(resumed.sandbox.value.writeScope(workspace: "/w", home: "/h") == .roots(["/w"]))
        let narrowed = files.applying(
            session: SandboxSection(write: [.anywhere, .workspace]), flaggedNetwork: false, flaggedWrite: false,
            flaggedRead: false)
        #expect(narrowed.sandbox.value.write == [.workspace], "a narrower scope in the record still narrows")
    }

    @Test func `a file persists it, and a failed write leaves the session as it was`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-sbrec-\(UUID().uuidString).jsonl").path
        do {
            var file = try SessionFile.create(at: FilePath(path), durability: .none)
            try file.append(.user("hi"))
            try file.recordSandbox(strict)
        }
        do {
            let reopened = try SessionFile.open(at: FilePath(path), durability: .none)
            #expect(reopened.tree.sandbox == strict && reopened.issues.isEmpty)
        }
        var failing = try SessionFile.open(at: FilePath(path), durability: .none) { _, _ throws(SessionFileError) in
            throw .io(.write, errno: EIO)
        }
        #expect(throws: SessionFileError.io(.write, errno: EIO)) { try failing.recordSandbox(SandboxSection()) }
        #expect(failing.tree.sandbox == strict, "undone in memory")
    }
}
