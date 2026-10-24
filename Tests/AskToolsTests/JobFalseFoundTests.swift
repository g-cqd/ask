import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The same fault through a real job: `wait` reports `found` for a text the command did not print.
@Suite("A wait finds only text the command printed", .timeLimit(.minutes(1)))
struct JobFalseFoundTests {
    /// Runs `command` to its end with `keeping` bytes kept at each end, then waits for `text`.
    private func wait(for text: String, after command: String, keeping: Int) async throws -> Job.WaitResult {
        let root = FileManager.default.temporaryDirectory.appending(path: "ask-jobs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let job = JobTable()
            .start(
                command, in: ToolContext(workingDirectory: root.path), keepsInputOpen: false, keeping: keeping,
                observe: { _ in })
        await job.ended()
        return await job.wait(for: Array(text.utf8))
    }

    @Test func `a text split across the omitted middle is not reported as found`() async throws {
        let result = try await wait(for: "Read", after: "printf 'abRezzzzzzzzadcd'", keeping: 4)
        #expect(result == .ended, "the command never printed Read")
    }

    @Test func `a text at either end of the output, or across a stream that lost nothing, is still found`() async throws
    {
        #expect(try await wait(for: "Head", after: "printf 'Headzzzzzzzzzzzz'", keeping: 4) == .found)
        #expect(try await wait(for: "Tail", after: "printf 'zzzzzzzzzzzzTail'", keeping: 4) == .found)
        #expect(try await wait(for: "Read", after: "printf 'abReadcd'", keeping: 4) == .found)
    }
}
