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
                ToolContext(workingDirectory: root.path, outputDirectory: root.path),
            keepsInputOpen: true,
            keeping: 1000,
            observe: { _ in }
        )
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

    @Test func `a snapshot cut mid-UTF-8 scalar in recent output produces no U+FFFD`() async throws {
        let table = JobTable()
        let seen = Printed("END")
        // 1 ASCII byte + 2,100 two-byte 'é's (4,200 bytes) + "END" (3 bytes) = 4,204 bytes;
        // the last 4,096 bytes start at offset 108, which is the second (continuation) byte of an 'é'.
        _ = table.start(
            "printf 'x'; for i in $(seq 1 210); do printf 'éééééééééé'; done; printf 'END'; read hold",
            in: ToolContext(workingDirectory: "/tmp", outputDirectory: nil),
            keepsInputOpen: true,
            keeping: 1_000,
            observe: { seen.received($0) }
        )
        await seen.seen()
        let snapshot = try #require(table.snapshot(of: "job-1"))
        #expect(snapshot.output.hasPrefix("… earlier output not shown\n"))
        #expect(snapshot.output.hasSuffix("END") && !snapshot.output.contains("\u{FFFD}"))
        await table.stopAll()
    }
}
