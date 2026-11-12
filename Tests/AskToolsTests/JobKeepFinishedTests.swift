import AskAgentCore
import Testing

@testable import AskTools

/// `jobs.keepFinished` (the owner, 2026-11-06; t232): every finished job is kept by default; with a limit, the oldest finished ones
/// past it are let go, a running one never, and a job tool asked about one let go says so.
@Suite("Finished jobs past jobs.keepFinished are let go, oldest first")
struct JobKeepFinishedTests {
    private func start(_ table: JobTable, _ command: String, open: Bool = false) -> Job {
        table.start(
            command,
            in: ToolContext(workingDirectory: "/tmp"),
            keepsInputOpen: open,
            keeping: 1000,
            observe: { _ in }
        )
    }

    @Test func `all are kept by default; a limit lets the oldest finished go, and never a running one`() async {
        let table = JobTable()
        let first = start(table, "true")
        let second = start(table, "true")
        await first.ended()
        await second.ended()
        let running = start(table, "read hold", open: true)
        #expect(table.job(first.id) != nil && table.job(second.id) != nil, "unlimited by default")
        table.keepFinished = 1
        #expect(table.job(first.id) == nil, "the oldest finished one is let go")
        #expect(table.job(second.id) === second && table.job(running.id) === running)
        table.keepFinished = 0
        #expect(table.job(second.id) == nil && table.job(running.id) === running, "a running job is never let go")
        await table.stopAll()
    }

    @Test func `a job started past the limit lets the oldest finished go`() async {
        let table = JobTable()
        table.keepFinished = 1
        let first = start(table, "true")
        await first.ended()
        let second = start(table, "true")
        await second.ended()
        let third = start(table, "true")
        #expect(table.job(first.id) == nil && table.job(second.id) === second && table.job(third.id) === third)
        await table.stopAll()
    }

    @Test func `a job tool asked about a job let go says so, by either of its names`() async throws {
        let table = JobTable()
        let job = start(table, "true")
        await job.ended()
        table.keepFinished = 0
        let access = JobAccess(jobs: table, clock: ContinuousClock())
        for name in [job.id, "#" + job.displayID] {
            let error = #expect(throws: ToolFailure.self) { try access.job(name) }
            #expect(
                error?.output.content.contains("jobs.keepFinished") == true,
                "\(name): \(String(describing: error))"
            )
        }
        let unknown = #expect(throws: ToolFailure.self) { try access.job("job-999") }
        #expect(unknown?.output.content == "No job named job-999.")
    }
}
