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

    @Test func `wait finds existing output using a display alias without rerouting the job block`() async {
        let job = await start()
        let reply = await JobActionTool(jobs: jobs)
            .run(
                input(##"{"job":"#\##(job.displayID)","action":"wait","wait_for_output":"READY"}"##), in: context)
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

    @Test func `input can wait transitively for output after the sent line`() async throws {
        let job = await start("echo READY; read line; echo GOT-$line; read hold")
        let clock = TestClock()
        let tool = JobActionTool(jobs: jobs, clock: clock)
        try #require(String(decoding: tool.definition.inputSchema.bytes, as: UTF8.self).contains("wait_for_output"))
        let reply = await tool.run(
            input(#"{"job":"job-1","text":"hello\n","wait_for_output":"GOT-hello"}"#), in: context)
        let status = job.status
        await jobs.stopAll()
        #expect(!reply.isError && reply.content.contains("GOT-hello") && status == .running)
    }

    @Test func `invalid wait modes and unknown identities are refused without stopping another job`() async {
        let job = await start()
        for json in [
            #"{"job":"job-1","action":"stop","wait_for_output":"x"}"#,
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
