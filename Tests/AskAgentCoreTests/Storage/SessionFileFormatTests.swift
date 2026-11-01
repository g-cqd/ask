import Foundation
import System
import Testing

@testable import AskAgentCore

/// Session files kept framed (ADR-0138, phase 3 of roadmap 0182): every change survives reopening in each format, an encrypted one opens
/// only with its keys, a framed file is repaired as a JSONL one is, and `/encrypt`'s change of format keeps no copy of the file as it was.
@Suite
struct SessionFileFormatTests {
    static let formats = [
        SessionFormat(compressed: true, encrypted: false), SessionFormat(compressed: false, encrypted: true),
        SessionFormat(compressed: true, encrypted: true)
    ]
    private let directory: URL
    private let keyring: SessionKeyring

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-framed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let made = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        keyring = SessionKeyring(keys: made.keys, userKey: made.userKey)
    }

    private func path(_ name: String = "s.jsonl") -> FilePath { FilePath(directory.appending(path: name).path) }
    private func bytes(_ name: String = "s.jsonl") throws -> [UInt8] {
        [UInt8](try Data(contentsOf: directory.appending(path: name)))
    }
    private func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    /// A session of three entries and a move of the leaf, closed.
    private func written(_ format: SessionFormat, name: String = "s.jsonl") throws -> SessionTree {
        var file = try SessionFile.create(at: path(name), format: format, keyring: keyring)
        let root = try file.append(.user("the secret question"))
        _ = try file.append(.assistant("abandoned"))
        _ = try file.continuing(from: root, with: .assistant("kept"))
        try file.moveLeaf(to: root)
        return file.tree
    }

    @Test(arguments: formats)
    func `every change survives reopening, and the file is framed`(format: SessionFormat) throws {
        let tree = try written(format)
        let reopened = try SessionFile.open(at: path(), keyring: keyring)
        #expect(reopened.tree.entries == tree.entries && reopened.tree.leaf == tree.leaf)
        #expect(reopened.issues.isEmpty)
        #expect(reopened.format == format)
        #expect(try bytes().starts(with: Array("ASKF".utf8)))
        if format.encrypted {
            #expect(!String(decoding: try bytes(), as: UTF8.self).contains("secret"))
        }
    }

    @Test(arguments: formats)
    func `a reopened session appends where it left off`(format: SessionFormat) throws {
        _ = try written(format)
        do {
            var file = try SessionFile.open(at: path(), keyring: keyring)
            _ = try file.append(.assistant("after reopening"))
        }
        let reopened = try SessionFile.open(at: path(), keyring: keyring)
        #expect(reopened.tree.entries.count == 4)
        #expect(reopened.issues.isEmpty)
    }

    @Test
    func `an encrypted session is locked without its keys, and refuses another person's`() throws {
        _ = try written(SessionFormat(compressed: true, encrypted: true))
        #expect(throws: SessionFileError.locked) { _ = try SessionFile.open(at: path()) }
        let other = try SessionKeys.create(password: Array("pw".utf8), derivation: SessionKeysTests.quick)
        let otherRing = SessionKeyring(keys: other.keys, userKey: other.userKey)
        #expect(throws: SessionFileError.otherKey) { _ = try SessionFile.open(at: path(), keyring: otherRing) }
        #expect(throws: SessionFileError.locked) {
            _ = try SessionFile.create(at: path("new.jsonl"), format: .init(compressed: false, encrypted: true))
        }
    }

    @Test(arguments: formats)
    func `a torn framed file is repaired as a JSONL one is, keeping the original`(format: SessionFormat) throws {
        _ = try written(format)
        let whole = try bytes()
        try Data(whole.dropLast(5)).write(to: directory.appending(path: "s.jsonl"))
        do {
            var file = try SessionFile.open(at: path(), keyring: keyring)
            #expect(file.issues.contains { if case .tornFinalFrame = $0 { true } else { false } })
            #expect(file.tree.entries.count == 3, "the leaf move was the torn record")
            _ = try file.append(.assistant("after the crash"))
            _ = try file.append(.assistant("appended after the repair"))
        }
        #expect(try bytes("s.jsonl.damaged") == Array(whole.dropLast(5)))
        let reopened = try SessionFile.open(at: path(), keyring: keyring)
        #expect(reopened.issues.isEmpty)
        #expect(reopened.tree.entries.count == 5)
    }

    @Test(arguments: formats)
    func `a damaged frame keeps what precedes it, and the damaged file beside the repair`(format: SessionFormat) throws
    {
        _ = try written(format)
        var changed = try bytes()
        let header = try FramedHeader.parse(changed).bytes.count
        // Inside the second frame: the header line is the first.
        let first = Int(FrameFormat.readLE32(changed, at: header)) + FrameFormat.frameHeaderLength
        changed[header + first + FrameFormat.frameHeaderLength + 2] ^= 0x01
        try Data(changed).write(to: directory.appending(path: "s.jsonl"))
        var file = try SessionFile.open(at: path(), keyring: keyring)
        #expect(file.issues.contains(.damagedFrame(frame: 1)))
        #expect(file.tree.entries.isEmpty)
        _ = try file.append(.user("again"))
        #expect(try bytes("s.jsonl.damaged") == changed)
    }

    @Test
    func `changing the format rewrites the session, and keeps no copy of it as it was`() throws {
        _ = try written(.plain)
        do {
            var file = try SessionFile.open(at: path())
            try file.change(to: SessionFormat(compressed: true, encrypted: true), keyring: keyring)
            #expect(!String(decoding: try bytes(), as: UTF8.self).contains("secret"))
            _ = try file.append(.assistant("now encrypted"))
        }
        let encrypted = try SessionFile.open(at: path(), keyring: keyring)
        #expect(encrypted.issues.isEmpty)
        #expect(encrypted.tree.entries.count == 4)
        _ = consume encrypted
        do {
            var file = try SessionFile.open(at: path(), keyring: keyring)
            try file.change(to: .plain)
            #expect(String(decoding: try bytes(), as: UTF8.self).contains("now encrypted"))
        }
        #expect(try names() == ["s.jsonl"])
        let reopened = try SessionFile.open(at: path())
        #expect(reopened.tree.entries.count == 4)
        #expect(reopened.format == .plain)
    }

    @Test
    func `a fork of an encrypted session is encrypted under a data key of its own`() throws {
        _ = try written(SessionFormat(compressed: false, encrypted: true))
        let file = try SessionFile.open(at: path(), keyring: keyring)
        _ = try file.fork(to: path("fork.jsonl"))
        let fork = try SessionFile.open(at: path("fork.jsonl"), keyring: keyring)
        #expect(fork.format == file.format)
        #expect(try FramedHeader.parse(bytes("fork.jsonl")).envelope != FramedHeader.parse(bytes()).envelope)
        #expect(!fork.tree.entries.isEmpty)
    }

    @Test
    func `the archive's limit counts what a compressed file holds, not its size on disk`() throws {
        do {
            var file = try SessionFile.create(at: path(), format: SessionFormat(compressed: true, encrypted: false))
            for _ in 0 ..< 64 { _ = try file.append(.assistant(String(repeating: "same words again ", count: 400))) }
        }
        let size = try bytes().count
        let limits = SessionLog.Limits(maximumLineBytes: 1 << 20, maximumArchiveBytes: size * 4)
        #expect(throws: SessionFileError.self) { _ = try SessionFile.open(at: path(), limits: limits) }
        #expect(throws: Never.self) { _ = try SessionFile.open(at: path(), limits: .standard) }
    }
}
