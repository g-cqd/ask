import AskAgentCore
import Foundation
import Testing

@testable import AskTools

@Suite("Background snapshots never consume model output", .timeLimit(.minutes(1)))
struct JobSnapshotTests {
    @Test func `snapshots retain output and final status after tool reads and file cleanup`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-job-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let table = JobTable()
        let job = table.start(
            "read word; printf '%s\\n' \"$word\"; read hold",
            in:
                ToolContext(workingDirectory: root.path, outputDirectory: root.path), keepsInputOpen: true,
            keeping: 1000, observe: { _ in })
        job.markBackgrounded()
        var changes = job.outputChanges().makeAsyncIterator()
        _ = await changes.next()
        #expect(job.write(Array("hello\n".utf8)))
        _ = await changes.next()
        let live = try #require(table.snapshot(of: job.id))
        #expect(live.output == "hello\n" && live.status == .running && live.lines == 1)
        #expect(job.takeOutput() == "hello\n")
        #expect(table.snapshot(of: job.id)?.output == "hello\n")
        await table.stopAll()
        job.discardFile()
        let final = try #require(table.snapshot(of: job.id))
        #expect(final.output == "hello\n" && final.endedAt != nil && final.status != .running)
        #expect(job.takeOutput().isEmpty)
    }
}
