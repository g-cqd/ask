import AskAgentCore
import Testing

/// A session keeps what it cannot read (ADR-0144): a record of a type, or an entry of a kind, that a newer ask wrote is kept, written
/// back on a rewrite as it came, never read, and no damage; a known record or kind that is broken still is.
@Suite("A newer ask's records and entries are kept, not read, and not damage")
struct SessionUnknownTests {
    private let header = #"{"type":"session","version":2}"#
    private let threadRecord = #"{"id":"x-1","note":"from a newer ask","type":"future_record"}"#
    private let futureEntry =
        #"{"id":"b","parent":"a","payload":{"kind":"fork_point","name":"thread-1"},"type":"entry"}"#

    private func entry(_ id: String, parent: String? = nil, _ text: String = "x") -> String {
        let parentField = parent.map { #""parent":"\#($0)","# } ?? ""
        return #"{"id":"\#(id)",\#(parentField)"payload":{"kind":"user","text":"\#(text)"},"type":"entry"}"#
    }

    private func log(_ lines: [String]) -> [UInt8] { Array((lines.joined(separator: "\n") + "\n").utf8) }

    private func lines(_ bytes: [UInt8]) -> [String] {
        String(decoding: bytes, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    @Test func `an unknown record and an unknown entry with a child under it load with no issue`() throws {
        let recovered = try SessionLog.recover(
            log([header, entry("a"), futureEntry, threadRecord, entry("c", parent: "b")])
        )
        #expect(recovered.issues.isEmpty)
        #expect(recovered.tree.entries.map(\.id.description) == ["a", "b", "c"])
        #expect(recovered.tree.entries[2].parentID == EntryID("b"), "the child still hangs from the unknown entry")
        #expect(recovered.tree.unknownRecords.map { String(decoding: $0, as: UTF8.self) } == [threadRecord])
        guard case .unrecognized(let kind, _) = recovered.tree.entries[1].payload else {
            Issue.record("the unknown entry is not kept as unrecognized")
            return
        }
        #expect(kind == "fork_point")
    }

    @Test func `the context skips them, and the conversation reads straight through`() throws {
        let recovered = try SessionLog.recover(
            log([header, entry("a", "one"), futureEntry, entry("c", parent: "b", "two")])
        )
        let context = recovered.tree.context()
        #expect(context.map(\.id.description) == ["a", "b", "c"])
        let messages = RequestContext(context).messages
        #expect(messages.count == 1, "two user messages in a row join; the unknown one adds nothing")
    }

    @Test func `a rewrite writes both back as they came`() throws {
        let recovered = try SessionLog.recover(
            log([header, entry("a"), futureEntry, threadRecord, entry("c", parent: "b")])
        )
        let written = lines(try SessionLog.snapshot(recovered.tree))
        #expect(written.contains(futureEntry))
        #expect(written.contains(threadRecord))
        let again = try SessionLog.recover(try SessionLog.snapshot(recovered.tree))
        #expect(again.tree == recovered.tree && again.issues.isEmpty)
    }

    @Test func `a known kind that is broken is still damage`() throws {
        let broken = #"{"id":"b","parent":"a","payload":{"kind":"user"},"type":"entry"}"#
        let notJSON = #"{"id":"b","pay"#
        let recovered = try SessionLog.recover(log([header, entry("a"), broken, notJSON, entry("d", parent: "a")]))
        #expect(recovered.issues == [.malformedLine(line: 3), .malformedLine(line: 4)])
        #expect(recovered.tree.entries.map(\.id.description) == ["a", "d"])
    }
}
