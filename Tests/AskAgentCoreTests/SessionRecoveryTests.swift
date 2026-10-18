import AskAgentCore
import Testing

/// Damaged sessions load by default (ADR-0013). Convenience is measured against pi 1.3.0: ask keeps at
/// least what pi keeps, never loses content pi would keep, and reports every repair where pi is silent.
@Suite("A damaged session loads, and every repair is reported")
struct SessionRecoveryTests {
    private let header = #"{"type":"session","version":1}"#

    private func entry(_ id: String, parent: String? = nil, _ text: String = "x") -> String {
        let parentField = parent.map { #""parent":"\#($0)","# } ?? ""
        return #"{"id":"\#(id)",\#(parentField)"payload":{"kind":"user","text":"\#(text)"},"type":"entry"}"#
    }

    private func log(_ lines: [String], terminated: Bool = true) -> [UInt8] {
        Array((lines.joined(separator: "\n") + (terminated ? "\n" : "")).utf8)
    }

    private func ids(_ tree: SessionTree) -> [String] { tree.entries.map(\.id.description) }

    // MARK: - Clean

    @Test func `a clean log recovers with no issues`() throws {
        var tree = SessionTree()
        let root = try tree.append(.user("root"))
        _ = try tree.append(.assistant("one"))
        _ = try tree.continuing(from: root, with: .assistant("two"))
        let recovered = try SessionLog.recover(SessionLog.snapshot(tree))
        #expect(recovered.issues.isEmpty)
        #expect(recovered.tree.entries == tree.entries)
        #expect(recovered.tree.leaf == tree.leaf)
    }

    // MARK: - Damage at the end

    /// Diverges from pi 1.3.0 (ADR-0012): pi drops the torn record silently, and appends a newline to the
    /// file during load, which makes the fragment a permanent corrupt line. ask reports it and is pure.
    @Test func `a torn final record is dropped and reported`() throws {
        let bytes = log([header, entry("a"), entry("b", parent: "a"), #"{"id":"c","pa"#], terminated: false)
        let recovered = try SessionLog.recover(bytes)
        #expect(ids(recovered.tree) == ["a", "b"])
        #expect(recovered.tree.leaf == EntryID("b"))
        #expect(recovered.issues == [.tornFinalLine(line: 4)])
    }

    @Test func `a complete final record missing only its newline is kept`() throws {
        let bytes = log([header, entry("a"), entry("b", parent: "a")], terminated: false)
        let recovered = try SessionLog.recover(bytes)
        #expect(ids(recovered.tree) == ["a", "b"])
        #expect(recovered.issues == [.unterminatedFinalLine(line: 3)])
    }

    // MARK: - Damage in the middle

    /// Diverges from pi 1.3.0 (ADR-0012): pi skips the corrupt line silently and truncates context at the
    /// gap. ask keeps every intact entry, re-roots the orphan so its subtree stays reachable, and says so.
    @Test func `a corrupt line is skipped and its orphaned child becomes a root`() throws {
        let bytes = log([header, entry("a"), "{garbage", entry("c", parent: "b"), entry("d", parent: "c")])
        let recovered = try SessionLog.recover(bytes)
        #expect(ids(recovered.tree) == ["a", "c", "d"])
        #expect(recovered.tree.entry(EntryID("c"))?.parentID == nil)
        #expect(recovered.tree.context().map(\.id.description) == ["c", "d"])
        #expect(
            recovered.issues == [
                .malformedLine(line: 3), .orphanedEntry(EntryID("c"), missingParent: EntryID("b"), line: 4)
            ])
    }

    @Test func `an overlong line is skipped and the rest still loads`() throws {
        let limits = SessionLog.Limits(maximumLineBytes: 96, maximumArchiveBytes: 1 << 20)
        let long = entry("big", parent: "a", String(repeating: "y", count: 200))
        let bytes = log([header, entry("a"), long, entry("b", parent: "a")])
        let recovered = try SessionLog.recover(bytes, limits: limits)
        #expect(ids(recovered.tree) == ["a", "b"])
        #expect(recovered.issues == [.lineTooLong(line: 3)])
    }

    // MARK: - Headers

    /// Diverges from pi 1.3.0 (ADR-0012): pi returns no entries at all when the header does not parse.
    @Test func `a corrupt header still loads every intact message`() throws {
        let bytes = log(["{corrupt header", entry("a"), entry("b", parent: "a")])
        let recovered = try SessionLog.recover(bytes)
        #expect(ids(recovered.tree) == ["a", "b"])
        #expect(recovered.issues == [.malformedLine(line: 1), .missingHeader])
    }

    @Test func `a log with no header loads with a report`() throws {
        let recovered = try SessionLog.recover(log([entry("a"), entry("b", parent: "a")]))
        #expect(ids(recovered.tree) == ["a", "b"])
        #expect(recovered.issues == [.missingHeader])
    }

    @Test func `an empty file is an empty session with a report`() throws {
        let recovered = try SessionLog.recover([])
        #expect(recovered.tree.entries.isEmpty)
        #expect(recovered.issues == [.missingHeader])
    }

    @Test func `an unknown format version is still refused`() throws {
        let bytes = log([#"{"type":"session","version":99}"#, entry("a")])
        #expect(throws: SessionLogError.unsupportedVersion(99)) { try SessionLog.recover(bytes) }
    }

    @Test func `an oversized archive is still refused`() throws {
        let bytes = log([header, entry("a")])
        let limits = SessionLog.Limits(maximumLineBytes: 1 << 20, maximumArchiveBytes: bytes.count - 1)
        #expect(throws: SessionLogError.archiveTooLarge(bytes.count)) {
            try SessionLog.recover(bytes, limits: limits)
        }
    }

    // MARK: - Structure

    /// Matches pi 1.3.0's fallback to the last entry, but reported instead of silent.
    @Test func `an unknown leaf falls back to the last surviving entry`() throws {
        let bytes = log([header, entry("a"), entry("b", parent: "a"), #"{"id":"ghost","type":"leaf"}"#])
        let recovered = try SessionLog.recover(bytes)
        #expect(recovered.tree.leaf == EntryID("b"))
        #expect(recovered.issues == [.ignoredLeaf(EntryID("ghost"), line: 4)])
    }

    /// Diverges from pi 1.3.0 (ADR-0012): pi's index keeps the last duplicate. ask keeps the first, since
    /// children written after it were written against it.
    @Test func `a duplicate identifier keeps the first entry`() throws {
        let bytes = log([header, entry("a", "first"), entry("a", "second")])
        let recovered = try SessionLog.recover(bytes)
        #expect(recovered.tree.entries.map(\.payload) == [.user("first")])
        #expect(recovered.issues == [.duplicateEntry(EntryID("a"), line: 3)])
    }

    /// Diverges from pi 1.3.0 (ADR-0012): with a boundary it cannot find, pi shows the summary and drops
    /// everything before it. ask splices the bad compaction out and keeps the raw messages it would hide.
    @Test func `a compaction with a boundary off its branch is spliced out`() throws {
        let compaction =
            #"{"id":"c","parent":"x","payload":{"firstKept":"other","kind":"compaction","summary":"s"},"type":"entry"}"#
        let bytes = log([
            header, entry("root"), entry("other", parent: "root"), entry("x", parent: "root"), compaction,
            entry("after", parent: "c")
        ])
        let recovered = try SessionLog.recover(bytes)
        #expect(ids(recovered.tree) == ["root", "other", "x", "after"])
        #expect(recovered.tree.entry(EntryID("after"))?.parentID == EntryID("x"))
        #expect(recovered.tree.context().map(\.id.description) == ["root", "x", "after"])
        #expect(recovered.issues == [.droppedCompaction(EntryID("c"), boundary: EntryID("other"), line: 5)])
    }

    @Test func `a header after records is skipped as misplaced`() throws {
        let recovered = try SessionLog.recover(log([entry("a"), header, entry("b", parent: "a")]))
        #expect(ids(recovered.tree) == ["a", "b"])
        #expect(recovered.issues == [.missingHeader, .malformedLine(line: 2)])
    }

    @Test func `a leaf naming a spliced compaction lands on its replacement parent`() throws {
        let compaction =
            #"{"id":"c","parent":"x","payload":{"firstKept":"other","kind":"compaction","summary":"s"},"type":"entry"}"#
        let bytes = log([
            header, entry("root"), entry("other", parent: "root"), entry("x", parent: "root"), compaction,
            entry("after", parent: "c"), #"{"id":"c","type":"leaf"}"#
        ])
        let recovered = try SessionLog.recover(bytes)
        #expect(recovered.tree.leaf == EntryID("x"))
        #expect(recovered.issues == [.droppedCompaction(EntryID("c"), boundary: EntryID("other"), line: 5)])
    }

    // MARK: - Repairs are durable

    @Test func `re-saving a recovered session produces a clean log`() throws {
        let damaged = log([header, entry("a"), "{garbage", entry("c", parent: "b"), #"{"id":"d""#], terminated: false)
        let recovered = try SessionLog.recover(damaged)
        #expect(!recovered.issues.isEmpty)
        let resaved = try SessionLog.snapshot(recovered.tree)
        let strict = try SessionLog.decode(resaved)
        #expect(strict.entries == recovered.tree.entries)
        #expect(strict.leaf == recovered.tree.leaf)
        #expect(try SessionLog.recover(resaved).issues.isEmpty)
    }
}
