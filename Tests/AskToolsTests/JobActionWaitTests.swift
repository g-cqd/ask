import AemiTesting
import AskAI
import AskAgentCore
import Testing

@testable import AskTools

@Suite("Existing-job waits never take ownership of the launched process", .timeLimit(.minutes(1)))
struct JobActionWaitTests {
    private let jobs = JobTable()
    private let context = ToolContext(workingDirectory: "/tmp")
    private func input(_ text: String) -> JSONObject { try! JSONObject(validating: Array(text.utf8)) }

    private func start(_ command: String = "echo READY; read hold") async -> Job {
        let ready = Printed("READY")
        let job = jobs.start(command, in: context, keepsInputOpen: true, keeping: 1000) { ready.received($0) }
        await ready.seen()
        return job
    }

    @Test func `a wait by display alias returns what the job printed, without rerouting the job block`() async throws {
        let job = await start()
        let clock = TestClock()
        let tool = JobActionTool(jobs: jobs, clock: clock)
        let task = Task { await tool.run(input(##"{"job":"#\##(job.displayID)","action":"wait"}"##), in: context) }
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(60))
        let reply = await task.value
        let running = job.status
        await jobs.stopAll()
        #expect(!reply.isError && reply.content.contains("READY"))
        #expect(reply.content.contains(job.id) && running == .running)
        #expect(reply.backgroundJob == nil)
    }

    @Test func `wait returns an already-ended job's output and nonzero exit status`() async {
        let job = await start("echo READY; exit 7")
        await job.ended()
        let reply = await JobActionTool(jobs: jobs).run(input(#"{"job":"job-1","action":"wait"}"#), in: context)
        #expect(reply.isError && reply.content.contains("READY") && reply.content.contains("[exit 7]"))
    }

    @Test(arguments: [false, true])
    func `timeout and cancellation leave an existing job running`(_ cancel: Bool) async throws {
        let job = await start()
        let clock = TestClock()
        let tool = JobActionTool(jobs: jobs, clock: clock)
        // Capability assertion makes the old surface fail before waiting on a timer it never registers.
        try #require(String(decoding: tool.definition.inputSchema.bytes, as: UTF8.self).contains(#""wait""#))
        let task = Task { await tool.run(input(#"{"job":"job-1","action":"wait","timeout_seconds":7}"#), in: context) }
        try await clock.waitForSleepers(count: 1)
        if cancel { task.cancel() } else { clock.advance(by: .seconds(7)) }
        let reply = await task.value
        let status = job.status
        await jobs.stopAll()
        #expect(reply.content.contains(cancel ? "aborted" : "within 7 s"))
        #expect(status == .running && reply.backgroundJob == nil)
    }

    /// ADR-0159: a text, a port or a file is waited for where the command starts. Given to `job`, it is refused with where
    /// it goes: ignored, the wait would sit out its whole time for something it was never watching.
    @Test func `job declares no wait_for, and says where one goes`() async {
        let job = await start()
        let tool = JobActionTool(jobs: jobs, clock: TestClock())
        #expect(!String(decoding: tool.definition.inputSchema.bytes, as: UTF8.self).contains("wait_for"))
        for given in [#""wait_for_output":"READY""#, #""wait_for_port":8080"#, #""wait_for_file":"flag""#] {
            let reply = await tool.run(input(#"{"job":"job-1","action":"wait",\#(given)}"#), in: context)
            #expect(reply.isError && reply.content.contains("bash's wait_for"), "\(given): \(reply.content)")
        }
        let status = job.status
        await jobs.stopAll()
        #expect(status == .running)
    }

    @Test func `invalid wait modes and unknown identities are refused without stopping another job`() async {
        let job = await start()
        for json in [
            #"{"job":"job-1","action":"wait","text":"oops\n"}"#,
            #"{"job":"missing","action":"wait"}"#
        ] {
            let reply = await JobActionTool(jobs: jobs).run(input(json), in: context)
            #expect(reply.isError)
            #expect(job.status == .running)
        }
        await jobs.stopAll()
    }
}
