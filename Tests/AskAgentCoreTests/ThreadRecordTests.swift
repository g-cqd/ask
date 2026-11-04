import AemiIO
import AskAgentCore
import Foundation
import System
import Testing

/// Threads kept with the session (roadmap 0195): where each started and merged, in main's session; whose thread it is, in its own.
@Suite("A session keeps its threads' records, outside the conversation")
struct ThreadRecordTests {
    private let started = ThreadRecord.started(
        "thread-1",
        parent: nil,
        prompt: "look into X",
        file: "/tmp/t1.jsonl",
        at: EntryID("3")
    )
    private let merged = ThreadRecord.merged("thread-1", summary: "It is fine.", at: EntryID("5"))

    @Test func `the records come back from a snapshot as they were, and stay out of the conversation`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-threadrecord-\(UUID().uuidString).jsonl")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let recorder = SessionRecorder(try SessionFile.create(at: FilePath(path), durability: .none))
        try recorder.append(.user("one"))
        try recorder.recordThread(started)
        try recorder.recordThread(merged)
        try recorder.recordThread(.renamed("thread-1", to: "parser work"))
        let reread = try SessionLog.recover(Array(try Data(contentsOf: URL(fileURLWithPath: path))))
        #expect(reread.issues.isEmpty)
        #expect(reread.tree.threads == [started, merged, .renamed("thread-1", to: "parser work")])
        #expect(reread.tree.entries.count == 1 && reread.tree.context().count == 1, "no entry, no context")
        let again = try SessionLog.recover(try SessionLog.snapshot(reread.tree))
        #expect(
            again.tree.threads.count == 3 && again.tree.threads.last?.title == "parser work",
            "a rewrite keeps them"
        )
    }

    @Test func `a thread's own session says so, and a session listing sees it`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-threadself-\(UUID().uuidString).jsonl")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let recorder = SessionRecorder(try SessionFile.create(at: FilePath(path), durability: .none))
        try recorder.append(.user("look into X"))
        #expect(SessionSummary(readingFrom: path)?.isThread == false)
        try recorder.recordThread(.identity("thread-1", of: "/tmp/main.jsonl"))
        #expect(SessionSummary(readingFrom: path)?.isThread == true)
    }
}
