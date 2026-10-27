internal import AskAgentCore
internal import Foundation
internal import Testing

@testable import AskTools

@Suite("Job output changes", .timeLimit(.minutes(1)))
struct JobOutputChangesTests {
    @Test func `a focused reader sees output that arrives after its initial snapshot`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-output-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let table = JobTable()
        let job = table.start(
            "read word; echo \"$word\"; read hold",
            in: ToolContext(workingDirectory: root.path, outputDirectory: root.path),
            keepsInputOpen: true, keeping: 1000, observe: { _ in })
        var changes = job.outputChanges().makeAsyncIterator()
        #expect(await changes.next() != nil)
        #expect(job.write(Array("new output\n".utf8)))
        #expect(await changes.next() != nil)
        #expect(table.outputTail(of: job.id, maximumBytes: 1000) == "new output\n")
        let waited = try await WaitTool(jobs: table)
            .run(
                .init(job: job.id, outputContains: "new output", fileExists: nil, portOpen: nil, timeoutSeconds: 1),
                in: ToolContext(workingDirectory: root.path))
        #expect(waited.content.contains("new output\n"))
        #expect(!waited.isError)
        await table.stopAll()
        #expect(await changes.next() == nil)
    }
    @Test func `cancelling a lane subscription leaves the job running`() async {
        let table = JobTable()
        let job = table.start(
            "read hold", in: ToolContext(workingDirectory: "/tmp"), keepsInputOpen: true, keeping: 1000,
            observe: { _ in })
        let stream = job.outputChanges()
        let reader = Task { for await _ in stream {} }
        reader.cancel()
        await reader.value
        #expect(job.status == .running)
        await table.stopAll()
        var ended = job.outputChanges().makeAsyncIterator()
        #expect(await ended.next() != nil)
        #expect(await ended.next() == nil)
    }
}
