import AemiIO
import Foundation
import System
import Testing

@testable import AskAgentCore

@Suite("Persisting queued input does not lock out producers")
struct PromptQueueTests {
    @Test func `input arriving during persistence remains queued behind the recorded message`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-queue-\(UUID().uuidString).jsonl").path
        _ = try SessionFile.create(at: FilePath(path), durability: .none)
        let input = PromptQueue()
        let first = QueuedPrompt(id: 1, text: "First")
        let arrived = QueuedPrompt(id: 2, text: "During persistence")
        input.append(first)
        let session = SessionRecorder(
            try SessionFile.open(at: FilePath(path), durability: .none) {
                bytes, descriptor throws(SessionFileError) in
                // A reentrant producer proves no queue lock spans the write, without scheduling a racing task.
                input.append(arrived)
                try SessionFileIO.writeAll(bytes, to: descriptor)
            })
        #expect(try input.recordNext(finished: false, in: session) == first)
        #expect(input.remaining == [arrived])
        #expect(session.tree.entries.map(\.payload) == [.user("First")])
    }
}
