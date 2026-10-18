import AskAgentCore
import Testing

@Suite("The session log round-trips and refuses damaged archives")
struct SessionLogTests {
    private func lines(_ bytes: [UInt8]) -> [[UInt8]] {
        bytes.split(separator: 0x0A, omittingEmptySubsequences: false).map(Array.init)
    }

    private func join(_ lines: [[UInt8]]) -> [UInt8] {
        Array(lines.joined(separator: [0x0A]))
    }

    private func branchedTree() throws -> SessionTree {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        _ = try tree.append(.assistant("abandoned"))
        let kept = try tree.continuing(from: root, with: .assistant("kept"))
        _ = try tree.append(.compaction(summary: "checkpoint", firstKept: kept))
        _ = try tree.append(.user("after"))
        return tree
    }

    // MARK: - Round trips

    @Test func `a branched compacted session round trips`() throws {
        let tree = try branchedTree()
        let restored = try SessionLog.decode(SessionLog.snapshot(tree))
        #expect(restored.entries == tree.entries)
        #expect(restored.leaf == tree.leaf)
        #expect(restored.context() == tree.context())
    }

    @Test func `an empty session round trips`() throws {
        let restored = try SessionLog.decode(SessionLog.snapshot(SessionTree()))
        #expect(restored.entries.isEmpty)
        #expect(restored.leaf == nil)
    }

    @Test func `a checkout persists without a new entry`() throws {
        var tree = try branchedTree()
        let root = try #require(tree.entries.first).id
        try tree.moveLeaf(to: root)
        let restored = try SessionLog.decode(SessionLog.snapshot(tree))
        #expect(restored.leaf == root)
        #expect(restored.entries == tree.entries)
    }

    @Test func `a new root persists as a nil leaf`() throws {
        var tree = try branchedTree()
        try tree.moveLeaf(to: nil)
        let restored = try SessionLog.decode(SessionLog.snapshot(tree))
        #expect(restored.leaf == nil)
    }

    @Test func `appended records replay onto a snapshot`() throws {
        let before = try branchedTree()
        var after = before
        let added = try after.append(.assistant("appended"))
        let entry = try #require(after.entry(added))
        let bytes = try SessionLog.snapshot(before) + SessionLog.line(for: entry)
        let restored = try SessionLog.decode(bytes)
        #expect(restored.entries == after.entries)
        #expect(restored.leaf == added)
    }

    @Test func `a leaf record appended later overrides the last entry`() throws {
        let tree = try branchedTree()
        let root = try #require(tree.entries.first).id
        let bytes = try SessionLog.snapshot(tree) + SessionLog.line(forLeaf: root)
        #expect(try SessionLog.decode(bytes).leaf == root)
    }

    @Test func `text containing newlines stays on one record line`() throws {
        var tree = SessionTree()
        _ = try tree.append(.user("first\nsecond\r\nthird"))
        let bytes = try SessionLog.snapshot(tree)
        // header, one entry, one leaf record, and the empty tail after the final newline.
        #expect(lines(bytes).count == 4)
        #expect(try SessionLog.decode(bytes).entries == tree.entries)
    }

    /// Pins the wire format. Encoding twice in one process cannot fail; a literal can, so a format
    /// change, key order included, shows up here and forces a version decision.
    @Test func `the wire format is pinned byte for byte`() throws {
        var tree = SessionTree()
        _ = try tree.append(.user("hi"))
        let expected = """
            {"type":"session","version":1}
            {"id":"0","payload":{"kind":"user","text":"hi"},"type":"entry"}
            {"id":"0","type":"leaf"}

            """
        #expect(try SessionLog.snapshot(tree) == Array(expected.utf8))
    }

    @Test func `a new root is an explicit null leaf on the wire`() throws {
        #expect(try SessionLog.line(forLeaf: nil) == Array("{\"id\":null,\"type\":\"leaf\"}\n".utf8))
    }

    // MARK: - Damage

    /// Diverges from pi 1.3.0 (ADR-0012): pi trims the file and drops a torn final record silently.
    @Test func `a missing final newline is a torn line, not a dropped one`() throws {
        var bytes = try SessionLog.snapshot(try branchedTree())
        let count = lines(bytes).count - 1
        bytes.removeLast()
        #expect(throws: SessionLogError.tornFinalLine(line: count)) { try SessionLog.decode(bytes) }
    }

    /// Diverges from pi 1.3.0 (ADR-0012): pi's JSON.parse failure is caught and the record skipped.
    @Test func `a record cut mid-way is a torn line`() throws {
        var bytes = try SessionLog.snapshot(try branchedTree())
        let count = lines(bytes).count - 1
        bytes.removeLast(5)
        #expect(throws: SessionLogError.tornFinalLine(line: count)) { try SessionLog.decode(bytes) }
    }

    /// Diverges from pi 1.3.0 (ADR-0012): pi skips a malformed line and loads the rest silently.
    @Test func `a corrupt record is reported with its line number`() throws {
        var parts = lines(try SessionLog.snapshot(try branchedTree()))
        parts[2] = Array("{not json".utf8)
        #expect(throws: SessionLogError.malformedLine(line: 3)) { try SessionLog.decode(join(parts)) }
    }

    /// Diverges from pi 1.3.0 (ADR-0012): pi skips blank lines.
    @Test func `a blank line is malformed rather than skipped`() throws {
        var parts = lines(try SessionLog.snapshot(try branchedTree()))
        parts.insert([], at: 1)
        #expect(throws: SessionLogError.malformedLine(line: 2)) { try SessionLog.decode(join(parts)) }
    }

    @Test func `an archive without a header is rejected`() throws {
        var parts = lines(try SessionLog.snapshot(try branchedTree()))
        parts.removeFirst()
        #expect(throws: SessionLogError.missingHeader) { try SessionLog.decode(join(parts)) }
        #expect(throws: SessionLogError.missingHeader) { try SessionLog.decode([]) }
    }

    @Test func `a second header is malformed`() throws {
        var parts = lines(try SessionLog.snapshot(try branchedTree()))
        parts.insert(parts[0], at: 1)
        #expect(throws: SessionLogError.malformedLine(line: 2)) { try SessionLog.decode(join(parts)) }
    }

    @Test func `an unknown format version is rejected`() throws {
        var parts = lines(try SessionLog.snapshot(SessionTree()))
        parts[0] = Array(#"{"type":"session","version":99}"#.utf8)
        #expect(throws: SessionLogError.unsupportedVersion(99)) { try SessionLog.decode(join(parts)) }
    }

    @Test func `an unknown record type is malformed`() throws {
        var parts = lines(try SessionLog.snapshot(SessionTree()))
        parts.insert(Array(#"{"type":"mystery"}"#.utf8), at: 1)
        #expect(throws: SessionLogError.malformedLine(line: 2)) { try SessionLog.decode(join(parts)) }
    }

    @Test func `an overlong line is rejected before it is parsed`() throws {
        let limits = SessionLog.Limits(maximumLineBytes: 64, maximumArchiveBytes: 1 << 20)
        var tree = SessionTree()
        _ = try tree.append(.user(String(repeating: "x", count: 200)))
        #expect(throws: SessionLogError.lineTooLong(line: 2)) {
            try SessionLog.decode(SessionLog.snapshot(tree), limits: limits)
        }
    }

    @Test func `an oversized archive is rejected before it is split`() throws {
        let bytes = try SessionLog.snapshot(try branchedTree())
        let limits = SessionLog.Limits(maximumLineBytes: 1 << 20, maximumArchiveBytes: bytes.count - 1)
        #expect(throws: SessionLogError.archiveTooLarge(bytes.count)) {
            try SessionLog.decode(bytes, limits: limits)
        }
    }

    /// Diverges from pi 1.3.0 (ADR-0012): pi truncates context at a missing parent without reporting it.
    @Test func `structural errors surface as invalid archives`() throws {
        var parts = lines(try SessionLog.snapshot(SessionTree()))
        let orphan = #"{"id":"a","parent":"ghost","payload":{"kind":"user","text":"x"},"type":"entry"}"#
        parts.insert(Array(orphan.utf8), at: 1)
        #expect(throws: SessionLogError.invalidArchive(.unknownEntry(EntryID("ghost")))) {
            try SessionLog.decode(join(parts))
        }
    }

    @Test func `a leaf record cannot point forward to an entry written later`() throws {
        var parts = lines(try SessionLog.snapshot(SessionTree()))
        let entry = #"{"id":"a","payload":{"kind":"user","text":"x"},"type":"entry"}"#
        parts.insert(Array(#"{"id":"a","type":"leaf"}"#.utf8), at: 1)
        parts.insert(Array(entry.utf8), at: 2)
        parts.remove(at: 3)  // drop the trailing null leaf so the final leaf would be valid
        #expect(throws: SessionLogError.invalidArchive(.unknownEntry(EntryID("a")))) {
            try SessionLog.decode(join(parts))
        }
    }

    /// Diverges from pi 1.3.0 (ADR-0012): pi falls back to the last entry for an unknown leaf.
    @Test func `a leaf record must name an entry already written`() throws {
        var parts = lines(try SessionLog.snapshot(SessionTree()))
        parts.insert(Array(#"{"id":"ghost","type":"leaf"}"#.utf8), at: 1)
        #expect(throws: SessionLogError.invalidArchive(.unknownEntry(EntryID("ghost")))) {
            try SessionLog.decode(join(parts))
        }
    }
}
