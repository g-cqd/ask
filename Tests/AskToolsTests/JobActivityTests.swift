import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// When each running job last wrote output (roadmap 0195, note n15): the sidebar spins for a job that writes and shows `$` for one that
/// has gone quiet.
@Suite("The job table says when each running job last wrote", .timeLimit(.minutes(1)))
struct JobActivityTests {
    private let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)
    private let jobs = JobTable()

    @Test func `a job that writes is reported at its output, one that does not is not, and an ended one is gone`()
        async throws
    {
        let before = ContinuousClock.now
        let writer = jobs.start("echo hello; sleep 60", in: context, keepsInputOpen: false, keeping: 1_000) { _ in }
        let quiet = jobs.start("sleep 60", in: context, keepsInputOpen: false, keeping: 1_000) { _ in }
        // Its output's notification: the time is set before readers are told.
        for await _ in writer.outputChanges() where jobs.activity[writer.id] != nil { break }
        let written = try #require(jobs.activity[writer.id])
        #expect(written >= before && written <= .now)
        #expect(jobs.activity[quiet.id] == nil, "nothing written, nothing reported")
        writer.stop()
        await writer.ended()
        #expect(jobs.activity[writer.id] == nil, "only running jobs")
        quiet.stop()
        await quiet.ended()
    }
}
