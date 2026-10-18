import AemiIO
import Foundation
import System
import Testing

@testable import AskAgentCore

/// The session file: one record per write, nothing written on open, and a damaged original kept beside
/// its repair rather than overwritten. Each test owns a fresh directory, so none shares state.
@Suite("Session files persist every change and never lose a damaged original")
struct SessionFileTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func path(_ name: String) -> FilePath { FilePath(directory.appending(path: name).path) }
    private func bytes(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appending(path: name)))
    }
    private func write(_ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: directory.appending(path: name))
    }
    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path)
    }

    // MARK: - Creating and reopening

    @Test func `a new session opens clean and empty`() throws {
        _ = try SessionFile.create(at: path("s.jsonl"))
        let reopened = try SessionFile.open(at: path("s.jsonl"))
        let tree = reopened.tree
        #expect(tree.entries.isEmpty)
        #expect(reopened.issues.isEmpty)
    }

    @Test func `creating never overwrites an existing file`() throws {
        try write("s.jsonl", "precious\n")
        #expect(throws: SessionFileError.alreadyExists) { _ = try SessionFile.create(at: path("s.jsonl")) }
        #expect(try bytes("s.jsonl") == Array("precious\n".utf8))
    }

    @Test func `every change survives reopening`() throws {
        var file = try SessionFile.create(at: path("s.jsonl"))
        let root = try file.append(.user("root"))
        _ = try file.append(.assistant("abandoned"))
        _ = try file.continuing(from: root, with: .assistant("kept"))
        try file.moveLeaf(to: root)
        let written = file.tree
        let reopened = try SessionFile.open(at: path("s.jsonl"))
        let tree = reopened.tree
        #expect(tree.entries == written.entries)
        #expect(tree.leaf == written.leaf)
        #expect(reopened.issues.isEmpty)
    }

    @Test func `each change appends one line and leaves earlier bytes untouched`() throws {
        var file = try SessionFile.create(at: path("s.jsonl"))
        let before = try bytes("s.jsonl")
        _ = try file.append(.user("one"))
        let after = try bytes("s.jsonl")
        #expect(Array(after.prefix(before.count)) == before)
        #expect(after.dropFirst(before.count).filter { $0 == 0x0A }.count == 1)
    }

    @Test func `a rejected change writes nothing`() throws {
        var file = try SessionFile.create(at: path("s.jsonl"))
        _ = try file.append(.user("one"))
        let before = try bytes("s.jsonl")
        let tree = file.tree
        #expect(throws: SessionFileError.tree(.unknownEntry(EntryID("ghost")))) {
            _ = try file.continuing(from: EntryID("ghost"), with: .user("lost"))
        }
        #expect(try bytes("s.jsonl") == before)
        #expect(file.tree == tree)
    }

    @Test(arguments: [SessionFile.Durability.none, .barrier, .full])
    func `every durability level writes the same bytes`(durability: SessionFile.Durability) throws {
        var file = try SessionFile.create(at: path("s.jsonl"), durability: durability)
        _ = try file.append(.user("same"))
        var reference = SessionTree()
        _ = try reference.append(.user("same"))
        let expected = try SessionLog.snapshot(SessionTree()) + SessionLog.line(for: reference.entries[0])
        #expect(try bytes("s.jsonl") == expected)
    }

    // MARK: - Damage

    @Test func `opening a damaged file does not change it`() throws {
        let damaged =
            "{\"type\":\"session\",\"version\":1}\n{garbage\n{\"id\":\"a\",\"payload\":{\"kind\":\"user\",\"text\":\"x\"},\"type\":\"entry\"}\n{\"id\":\"b"
        try write("s.jsonl", damaged)
        let opened = try SessionFile.open(at: path("s.jsonl"))
        #expect(!opened.issues.isEmpty)
        #expect(try bytes("s.jsonl") == Array(damaged.utf8))
        #expect(!exists("s.jsonl.damaged"))
    }

    @Test func `the first write after a damaged open keeps the original and writes a clean file`() throws {
        let damaged =
            "{\"type\":\"session\",\"version\":1}\n{\"id\":\"a\",\"payload\":{\"kind\":\"user\",\"text\":\"x\"},\"type\":\"entry\"}\n{\"id\":\"b"
        try write("s.jsonl", damaged)
        var file = try SessionFile.open(at: path("s.jsonl"))
        let added = try file.append(.assistant("after the crash"))
        // The damaged bytes survive, untouched, under a name that says what they are.
        #expect(try bytes("s.jsonl.damaged") == Array(damaged.utf8))
        // The session file is now clean: it decodes strictly, with the new entry selected.
        let clean = try SessionLog.decode(bytes("s.jsonl"))
        #expect(clean.entries.map(\.id.description) == ["a", added.description])
        #expect(clean.leaf == added)
    }

    @Test func `a later repair does not overwrite an earlier damaged copy`() throws {
        let first = "{\"type\":\"session\",\"version\":1}\n{\"id\":\"a"
        try write("s.jsonl", first)
        var file = try SessionFile.open(at: path("s.jsonl"))
        _ = try file.append(.user("one"))
        let second = "{\"type\":\"session\",\"version\":1}\n{\"id\":\"z"
        try write("s.jsonl", second)
        var again = try SessionFile.open(at: path("s.jsonl"))
        _ = try again.append(.user("two"))
        #expect(try bytes("s.jsonl.damaged") == Array(first.utf8))
        #expect(try bytes("s.jsonl.damaged-2") == Array(second.utf8))
    }

    @Test func `writes after a repair append to the clean file`() throws {
        try write("s.jsonl", "{\"type\":\"session\",\"version\":1}\n{\"id\":\"a")
        var file = try SessionFile.open(at: path("s.jsonl"))
        _ = try file.append(.user("one"))
        let repaired = try bytes("s.jsonl")
        _ = try file.append(.user("two"))
        #expect(Array(try bytes("s.jsonl").prefix(repaired.count)) == repaired)
        #expect(!exists("s.jsonl.damaged-2"))
    }

    // MARK: - A failed write

    @Test func `a torn append is never appended to, and is kept as a damaged copy`() throws {
        var file = try SessionFile.create(at: path("s.jsonl"))
        let first = try file.append(.user("one"))
        var failuresLeft = 1
        var reopened = try SessionFile.open(at: path("s.jsonl"), durability: .barrier) {
            record, descriptor throws(SessionFileError) in
            // Once: write half the record, as a full disk would, then report the failure.
            let torn = failuresLeft > 0
            failuresLeft -= 1
            _ = try? descriptor.writeAll(torn ? Array(record.prefix(record.count / 2)) : record)
            if torn { throw .io(.write, errno: ENOSPC) }
        }
        #expect(throws: SessionFileError.io(.write, errno: ENOSPC)) { try reopened.append(.user("torn")) }
        let torn = try bytes("s.jsonl")
        #expect(reopened.tree.entries.map(\.id) == [first])
        // The next change rewrites the file from memory instead of appending after the fragment …
        let second = try reopened.append(.user("two"))
        #expect(try bytes("s.jsonl.damaged") == torn)
        #expect(try SessionLog.decode(bytes("s.jsonl")).entries.map(\.id) == [first, second])
        // … and later changes go to the clean file, not to the damaged copy that shares the old inode.
        let third = try reopened.continuing(from: first, with: .user("three"))
        #expect(try bytes("s.jsonl.damaged") == torn)
        #expect(try SessionLog.decode(bytes("s.jsonl")).entries.map(\.id) == [first, second, third])
    }

    @Test func `sessions default to an ordered flush`() throws {
        let file = try SessionFile.create(at: path("s.jsonl"))
        #expect(file.durability == .barrier)
        let reopened = try SessionFile.open(at: path("s.jsonl"))
        #expect(reopened.durability == .barrier)
    }

    // MARK: - Opening

    @Test func `opening a missing file reports it rather than creating one`() throws {
        #expect(throws: SessionFileError.io(.open, errno: ENOENT)) {
            _ = try SessionFile.open(at: path("absent.jsonl"))
        }
        #expect(!exists("absent.jsonl"))
    }

    @Test func `an oversized file is refused before it is read`() throws {
        try write("s.jsonl", String(repeating: "x", count: 4096))
        let limits = SessionLog.Limits(maximumLineBytes: 1024, maximumArchiveBytes: 1024)
        #expect(throws: SessionFileError.log(.archiveTooLarge(4096))) {
            _ = try SessionFile.open(at: path("s.jsonl"), limits: limits)
        }
    }

    // MARK: - Fork

    @Test func `fork writes the active branch to a new file`() throws {
        var file = try SessionFile.create(at: path("s.jsonl"))
        let root = try file.append(.user("root"))
        _ = try file.append(.assistant("other"))
        let chosen = try file.continuing(from: root, with: .assistant("chosen"))
        let fork = try file.fork(to: path("fork.jsonl"))
        let forkTree = fork.tree
        #expect(forkTree.entries.map(\.id) == [root, chosen])
        let reopened = try SessionFile.open(at: path("fork.jsonl"))
        let tree = reopened.tree
        #expect(tree.entries == forkTree.entries)
        #expect(tree.leaf == chosen)
    }

    @Test func `fork never overwrites an existing file`() throws {
        try write("fork.jsonl", "precious\n")
        let file = try SessionFile.create(at: path("s.jsonl"))
        #expect(throws: SessionFileError.alreadyExists) { _ = try file.fork(to: path("fork.jsonl")) }
        #expect(try bytes("fork.jsonl") == Array("precious\n".utf8))
    }
}
