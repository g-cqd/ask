import AemiIO
import AskAgentCore
import Foundation
import System
import Testing

/// A thread's own model is kept with the session (owner, 2026-11-27), and a thread record of an event a build does not have is kept
/// as a newer ask's, not read and not damage (ADR-0144), so this record opens in an older ask too.
@Suite("A thread's model is kept with the session")
struct ThreadModelRecordTests {
    @Test func `the model record comes back as written, and a reset as none`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-threadmodel-\(UUID().uuidString).jsonl")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let recorder = SessionRecorder(try SessionFile.create(at: FilePath(path), durability: .none))
        try recorder.append(.user("one"))
        try recorder.recordThread(.model("thread-1", "codex/gpt-6"))
        try recorder.recordThread(.model("thread-1", nil))
        let reread = try SessionLog.recover(Array(try Data(contentsOf: URL(fileURLWithPath: path))))
        #expect(reread.issues.isEmpty)
        #expect(reread.tree.threads == [.model("thread-1", "codex/gpt-6"), .model("thread-1", nil)])
    }

    @Test func `a thread record of an unknown event is kept as a newer ask's, and is no damage`() throws {
        let header = #"{"type":"session","version":1}"#
        let entry = #"{"id":"a","payload":{"kind":"user","text":"one"},"type":"entry"}"#
        let future = #"{"event":"paused","id":"thread-1","type":"thread"}"#
        let recovered = try SessionLog.recover(Array([header, entry, future].joined(separator: "\n").utf8) + [0x0A])
        #expect(recovered.issues.isEmpty)
        #expect(recovered.tree.threads.isEmpty)
        #expect(recovered.tree.unknownRecords.map { String(decoding: $0, as: UTF8.self) } == [future])
    }
}
