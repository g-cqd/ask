import AemiIO
import Foundation
import System
import Testing

@testable import AskAgentCore

/// A fork writes a branch of a session to a new file and leaves the original as it was (ADR-0094). It can stop at an earlier entry, so
/// the person can fork from before a prompt, and it never changes the original's selected entry.
@Suite("A fork holds one branch of a session in a file of its own and changes nothing of the original")
struct SessionForkTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-fork-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func path(_ name: String) -> FilePath { FilePath(directory.appending(path: name).path) }
    private func bytes(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appending(path: name)))
    }

    /// user one, reply, user two, reply, then back to the first reply and a different second prompt: two branches.
    private func branches(in file: inout SessionFile) throws -> [EntryID] {
        let one = try file.append(.user("one"))
        let reply = try file.append(.assistant("reply one"))
        try file.append(.user("two"))
        try file.append(.assistant("reply two"))
        try file.moveLeaf(to: reply)
        let other = try file.append(.user("two, differently"))
        return [one, reply, other]
    }

    private func made() throws -> SessionFile { try SessionFile.create(at: path("s.jsonl"), durability: .none) }

    @Test func `forking the active branch holds exactly that branch, and the original is byte for byte what it was`()
        throws
    {
        var file = try made()
        let ids = try branches(in: &file)
        let original = try bytes("s.jsonl")
        let forked = try file.fork(to: path("f.jsonl"))
        #expect(forked.tree.entries.map(\.id) == [ids[0], ids[1], ids[2]])
        #expect(forked.tree.leaf == ids[2])
        #expect(try bytes("s.jsonl") == original)
    }

    @Test func `forking up to an earlier entry stops there, and the original's selected entry does not move`() throws {
        var file = try made()
        let ids = try branches(in: &file)
        let forked = try file.fork(upTo: ids[0], to: path("f.jsonl"))
        #expect(forked.tree.entries.map(\.id) == [ids[0]] && forked.tree.leaf == ids[0])
        #expect(file.tree.leaf == ids[2], "the original is still where it was")
    }

    @Test func `forking up to before the first prompt holds nothing, and is a session that starts again`() throws {
        var file = try made()
        _ = try branches(in: &file)
        let forked = try file.fork(upTo: nil, to: path("f.jsonl"))
        #expect(forked.tree.entries.isEmpty && forked.tree.leaf == nil)
    }

    @Test func `an entry that is not there is refused, and no file is made`() throws {
        var file = try made()
        _ = try branches(in: &file)
        #expect(throws: SessionFileError.self) { _ = try file.fork(upTo: EntryID("nope"), to: path("f.jsonl")) }
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "f.jsonl").path))
    }

    @Test func `a file that is already there is never overwritten`() throws {
        var file = try made()
        let ids = try branches(in: &file)
        try Data("precious\n".utf8).write(to: directory.appending(path: "f.jsonl"))
        #expect(throws: SessionFileError.alreadyExists) { _ = try file.fork(upTo: ids[0], to: path("f.jsonl")) }
        #expect(try bytes("f.jsonl") == Array("precious\n".utf8))
    }

    @Test func `the strict sandbox the session ran under travels with the fork, so resuming it keeps it (ADR-0045)`()
        throws
    {
        var file = try made()
        let ids = try branches(in: &file)
        let strict = SandboxSection(write: [.workspace], network: SandboxPolicy.Network.none)
        try file.recordSandbox(strict)
        let forked = try file.fork(upTo: ids[1], to: path("f.jsonl"))
        #expect(forked.tree.sandbox == strict.strict)
        let again = try SessionLog.decode(bytes("f.jsonl"))
        #expect(again.sandbox == strict.strict, "and it is in the file, not only in memory")
    }

    @Test func `what is forked survives reopening, and holds its own lock`() throws {
        var file = try made()
        let ids = try branches(in: &file)
        let forked = try file.fork(upTo: ids[1], to: path("f.jsonl"))
        #expect(throws: SessionFileError.inUse) { _ = try SessionFile.open(at: path("f.jsonl"), durability: .none) }
        _ = forked
    }

    @Test func `the recorder forks into a recorder whose changes go to the new file only`() throws {
        var file = try made()
        let ids = try branches(in: &file)
        let recorder = SessionRecorder(file)
        let original = try bytes("s.jsonl")
        let forked = try recorder.fork(upTo: ids[1], to: path("f.jsonl"))
        let added = try forked.append(.user("on the fork"))
        #expect(forked.tree.entry(added)?.parentID == ids[1])
        #expect(try bytes("s.jsonl") == original)
        #expect(recorder.tree.leaf == ids[2])
    }
}
