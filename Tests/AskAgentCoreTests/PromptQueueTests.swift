import AemiIO
import Foundation
import Synchronization
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
                bytes,
                descriptor throws(SessionFileError) in
                // A reentrant producer proves no queue lock spans the write, without scheduling a racing task.
                input.append(arrived)
                try SessionFileIO.writeAll(bytes, to: descriptor)
            }
        )
        #expect(try input.recordNext(finished: false, in: session) == first)
        #expect(input.remaining == [arrived])
        #expect(session.tree.entries.map(\.payload) == [.user("First")])
    }

    @Test func `a message not yet taken can be withdrawn, and one being recorded cannot (roadmap 0174)`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-queue-\(UUID().uuidString).jsonl").path
        _ = try SessionFile.create(at: FilePath(path), durability: .none)
        let input = PromptQueue()
        input.append(QueuedPrompt(id: 1, text: "First"))
        input.append(QueuedPrompt(id: 2, text: "Second"))
        input.append(QueuedPrompt(id: 3, text: "Third"))
        #expect(input.withdraw(id: 2))
        #expect(!input.withdraw(id: 2), "already gone")
        let duringWrite = Mutex<Bool?>(nil)
        let session = SessionRecorder(
            try SessionFile.open(at: FilePath(path), durability: .none) { bytes, descriptor throws(SessionFileError) in
                // While the first is written it is the loop's: withdrawing it fails, and another may still go.
                duringWrite.withLock { $0 = input.withdraw(id: 1) }
                _ = input.withdraw(id: 3)
                try SessionFileIO.writeAll(bytes, to: descriptor)
            }
        )
        #expect(try input.recordNext(finished: false, in: session)?.id == 1)
        #expect(duringWrite.withLock { $0 } == false)
        #expect(
            input.remaining.isEmpty,
            "the third was withdrawn while the first was written, and the first left once recorded"
        )
    }

    @Test func `the recorded message leaves the queue by its id, not its place`() throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "ask-queue-\(UUID().uuidString).jsonl").path
        _ = try SessionFile.create(at: FilePath(path), durability: .none)
        let input = PromptQueue()
        let later = QueuedPrompt(id: 1, text: "Later", delivery: .followUp)
        input.append(later)
        input.append(QueuedPrompt(id: 2, text: "Now"))
        let session = SessionRecorder(try SessionFile.open(at: FilePath(path), durability: .none))
        #expect(try input.recordNext(finished: false, in: session)?.id == 2, "steering goes before a follow-up")
        #expect(input.remaining == [later])
    }
}
