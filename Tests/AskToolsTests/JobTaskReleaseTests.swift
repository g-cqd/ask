import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// A job lets go of the task that ran it once it ends (task t231). The table keeps every job, so the `job` tool can still read one that
/// ended; each kept its finished task, and a finished task keeps the memory its child tasks took from it. A session open thirty hours
/// held 1,560 jobs and 18,849 task stacks (19.7 MB); a release build kept about 14 task stacks per command, 1 once this let go.
@Suite("A job that ended holds no task", .timeLimit(.minutes(1)))
struct JobTaskReleaseTests {
    private let context = ToolContext(workingDirectory: "/tmp")

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `a command that ended leaves its job without the task that ran it`() async throws {
        let jobs = JobTable()
        let output = await BashTool(jobs: jobs).run(input(#"{"command":"echo done","shell":"/bin/bash"}"#), in: context)
        #expect(output.content.contains("done"))
        let job = try #require(jobs.job("job-1"))
        await job.ended()
        #expect(!job.holdsTask, "a finished job still holds its task, and with it its children's memory")
        #expect(jobs.job("job-1") != nil, "the job itself is kept, for the job tool")
    }

    @Test func `a job stopped while running lets go of its task too`() async throws {
        let jobs = JobTable()
        let output = await BashTool(jobs: jobs)
            .run(input(#"{"command":"sleep 30","yield_seconds":1,"shell":"/bin/bash"}"#), in: context)
        let id = try #require(output.backgroundJob)
        let job = try #require(jobs.job(id))
        #expect(job.holdsTask, "a running job holds its task, which a stop cancels")
        job.stop()
        await job.ended()
        #expect(!job.holdsTask)
    }
}
