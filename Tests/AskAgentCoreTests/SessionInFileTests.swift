import AskAI
import Foundation
import System
import Testing

@testable import AskAgentCore

/// A long session is not all held in memory (roadmap 0238, ADR-0165): what a request, the screen and a rewind's menu read is held, and
/// the payload of every other tool result and response stays in the file, read from it when asked, as the file has it.
@Suite("A session opened keeps in memory only what is read, and reads the rest from its file when asked")
struct SessionInFileTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-infile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var path: FilePath { FilePath(directory.appending(path: "s.jsonl").path) }
    private var bytes: [UInt8] { [UInt8](FileManager.default.contents(atPath: path.string) ?? Data()) }

    /// A text of `size` bytes that tells one entry from another.
    private func text(_ label: String, _ size: Int = 2_000) -> String {
        String(repeating: label + " ", count: size / (label.count + 1))
    }

    private func response(_ label: String) -> SessionPayload {
        .response(
            AssembledResponse(
                id: "r-" + label,
                model: "m",
                blocks: [.text(text(label))],
                stopReason: .endTurn,
                usage: TokenUsage(input: 1, output: 1),
                unrecognized: []
            )
        )
    }

    private func result(_ label: String, images: [ImagePart] = []) -> SessionPayload {
        .toolResult(callID: "c-" + label, content: text(label), isError: false, images: images, facts: ToolFacts())
    }

    /// Four turns of a prompt, a response and a tool result; then a compaction keeping the last two; then one more turn. Returns the
    /// identifier the compaction keeps from.
    private func session(compacting: Bool = true) throws -> EntryID {
        var file = try SessionFile.create(at: path)
        var kept: EntryID?
        for turn in 1 ... 4 {
            let prompt = try file.append(.user("prompt \(turn)"))
            if turn == 3 { kept = prompt }
            _ = try file.append(response("response\(turn)"))
            _ = try file.append(result("result\(turn)"))
        }
        if compacting, let kept { _ = try file.append(.compaction(summary: "summary", firstKept: kept)) }
        _ = try file.append(.user("after"))
        _ = try file.append(response("last"))
        return kept ?? EntryID("0")
    }

    @Test func `what no request reads stays in the file, and what one reads is held`() throws {
        let kept = try session()
        let file = try SessionFile.open(at: path)
        let tree = file.tree
        let branch = tree.activeBranch()
        let firstKept = try #require(branch.firstIndex { $0.id == kept })
        for (index, entry) in branch.enumerated() {
            let big = entry.kind == .response || entry.kind == .toolResult
            #expect(entry.isInFile == (big && index < firstKept), "\(index) \(entry.kind)")
            // What it cost is held beside it (roadmap 0239): a response's tokens are read without reading the file back.
            if entry.kind == .response { #expect(entry.spent?.usage == TokenUsage(input: 1, output: 1)) }
        }
        #expect(tree.inFileCount == 4, "the responses and results of turns 1 and 2")
        let (shown, earlier) = tree.sinceLastCompaction()
        #expect(earlier == firstKept && shown.first?.id == kept)
    }

    @Test func `an entry read from the file is the one that was written, and a rewrite of it is the same bytes`() throws
    {
        _ = try session()
        let hot = try SessionLog.decode(bytes)
        let cold = try SessionFile.open(at: path).tree
        #expect(cold.inFileCount > 0)
        #expect(cold.entries.map(\.payload) == hot.entries.map(\.payload))
        #expect(try SessionLog.snapshot(cold) == SessionLog.snapshot(hot))
        #expect(cold == hot)
    }

    @Test func `a session that was never compacted holds its whole branch, and leaves another branch in the file`()
        throws
    {
        let root: EntryID
        do {
            // Closed before reopening: a session has one writer at a time.
            var file = try SessionFile.create(at: path)
            root = try file.append(.user("root"))
            _ = try file.append(response("abandoned"))
            _ = try file.continuing(from: root, with: response("kept"))
            _ = try file.append(result("kept-result"))
        }
        let tree = try SessionFile.open(at: path).tree
        #expect(tree.entries.filter(\.isInFile).count == 1, "only the abandoned branch's response")
        #expect(tree.entries.first { $0.isInFile }?.parentID == root)
    }

    @Test func `a prompt, a record under the size and one with pictures are held wherever they are`() throws {
        do {
            var file = try SessionFile.create(at: path)
            let picture = ImagePart(mediaType: "image/png", data: Array(repeating: 7, count: 300))
            _ = try file.append(.user(text("prompt", 4_000)))
            _ = try file.append(
                .toolResult(callID: "tiny", content: "ok", isError: false, images: [], facts: ToolFacts())
            )
            _ = try file.append(result("pictured", images: [picture]))
            let compacted = try file.append(.assistant("x"))
            _ = try file.append(.compaction(summary: "s", firstKept: compacted))
        }
        let tree = try SessionFile.open(at: path).tree
        #expect(tree.inFileCount == 0, "\(tree.entries.map(\.kind))")
        #expect(tree.entries.count == 5)
    }

    /// Where each line starts is counted from the chunks read, and a line that spans chunks starts where it began.
    @Test(arguments: [1, 7, 100, 4_096, 1 << 20])
    func `a line is found again whatever the size of the chunks it was read in`(chunk: Int) throws {
        _ = try session()
        let hot = try SessionLog.decode(bytes)
        let descriptor = try FileDescriptor.open(path, .readOnly)
        defer { try? descriptor.close() }
        let source = try #require(ColdSource(path: path))
        let read = try SessionLogReader(chunkBytes: chunk)
            .recover(descriptor, limits: .standard, images: nil, source: source)
        #expect(read.issues.isEmpty)
        #expect(read.tree.inFileCount == 4)
        #expect(read.tree.entries.map(\.payload) == hot.entries.map(\.payload))
    }

    @Test func `damage is found and said when the file is opened, as it is when every payload is kept`() throws {
        _ = try session()
        var lines = String(decoding: bytes, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        lines.insert(
            "{\"type\":\"entry\",\"id\":\"ghost\",\"parent\":\"nobody\",\"payload\":"
                + String(repeating: "x", count: 900),
            at: 3
        )
        lines.insert(
            "{\"type\":\"entry\",\"id\":\"orphan\",\"parent\":\"nobody\",\"payload\":{\"kind\":\"assistant\",\"text\":\"\(text("o"))\"}}",
            at: 6
        )
        try Data(lines.joined(separator: "\n").utf8).write(to: URL(fileURLWithPath: path.string))
        let hot = try SessionLog.recover(bytes)
        let file = try SessionFile.open(at: path)
        #expect(!hot.issues.isEmpty)
        #expect(file.issues == hot.issues)
        #expect(file.tree.entries.map(\.id) == hot.tree.entries.map(\.id))
        #expect(file.tree.entries.map(\.parentID) == hot.tree.entries.map(\.parentID))
        #expect(file.tree.entries.map(\.payload) == hot.tree.entries.map(\.payload))
    }

    @Test func `a payload the file no longer has reads as missing, and is not written as what stands in for it`() throws
    {
        _ = try session()
        var file = try SessionFile.open(at: path)
        let gone = try #require(file.tree.entries.first { $0.isInFile })
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path.string))
        try handle.truncate(atOffset: 300)
        try handle.close()
        #expect(gone.readablePayload == nil)
        #expect(gone.payload == .assistant(SessionEntry.unreadableNote))
        #expect(throws: SessionLogError.self) { _ = try SessionLog.snapshot(file.tree) }
        let before = bytes
        #expect(throws: SessionFileError.self) { try file.rewrite() }
        #expect(bytes == before, "nothing was written")
    }

    @Test func `a rewrite reads what was left in the file before it replaces it, and leaves none there`() throws {
        _ = try session()
        let hot = try SessionLog.decode(bytes)
        do {
            var file = try SessionFile.open(at: path)
            #expect(file.tree.inFileCount > 0)
            try file.rewrite(keepingOriginal: false)
            #expect(file.tree.inFileCount == 0)
            #expect(file.tree == hot)
        }
        let reopened = try SessionFile.open(at: path)
        #expect(reopened.tree == hot && reopened.issues.isEmpty)
    }

    @Test func `entries copied out of a session do not keep it locked once it is closed`() throws {
        _ = try session()
        var copied: [SessionEntry] = []
        do {
            let file = try SessionFile.open(at: path)
            copied = file.tree.entries.filter(\.isInFile)
        }
        #expect(!copied.isEmpty)
        let again = try SessionFile.open(at: path)
        #expect(copied.allSatisfy { $0.readablePayload != nil }, "still readable")
        _ = consume again
    }
}
