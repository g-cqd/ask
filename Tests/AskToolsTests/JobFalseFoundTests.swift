import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The same fault through a real job: `wait` reports `found` for a text the command did not print.
@Suite("A wait finds only text the command printed", .timeLimit(.minutes(1)))
struct JobFalseFoundTests {
    @Test func `a text split across the omitted middle is not reported as found`() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let jobs = JobTable()
        let job = jobs.start(
            "printf 'abRezzzzzzzzadcd'", in: ToolContext(workingDirectory: root.path), keepsInputOpen: false,
            keeping: 4, observe: { _ in })
        await job.ended()
        let result = await job.wait(for: Array("Read".utf8))
        withKnownIssue("the wait searches the kept head and tail as if they were adjacent") {
            #expect(result == .ended)
        }
        #expect(result == .found || result == .ended)
    }
}
