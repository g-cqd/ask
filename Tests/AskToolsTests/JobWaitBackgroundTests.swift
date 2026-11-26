import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// Owner, 2026-11-26: the person ends the model's wait on a job with Ctrl+B, as a command's (roadmap 0173), so a message can steer during
/// a long wait; and the request ends only the waits of the conversation it names, main's or a thread's.
@Suite("Ctrl+B ends a job tool's wait, and only the waits of the conversation shown")
struct JobWaitBackgroundTests {
    private let jobs = JobTable(
        environment: ProcessInfo.processInfo.environment.merging(["SHELL": "/bin/bash"]) { _, shell in shell }
    )
    private let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)

    private func startJob() async throws -> String {
        let input = try JSONObject(validating: Array(#"{"command":"sleep 30","yield_seconds":1}"#.utf8))
        let started = await BashTool(jobs: jobs).run(input, in: context)
        return try #require(started.backgroundJob)
    }

    @Test func `a wait the person ends returns with the job still running`() async throws {
        let id = try await startJob()
        let wait = try JSONObject(validating: Array(#"{"job":"\#(id)","action":"wait","timeout_seconds":60}"#.utf8))
        async let output = JobActionTool(jobs: jobs).run(wait, in: context)
        await jobs.foreground.waitUntilWaiting()
        #expect(jobs.sendForegroundToBackground())
        let result = await output
        #expect(result.content.contains("the person ended this wait") && !result.isError)
        #expect(jobs.job(id)?.status == .running)
        jobs.job(id)?.stop()
        await jobs.job(id)?.ended()
    }

    @Test func `main's request leaves a thread's wait alone, and the thread's ends it`() async throws {
        let id = try await startJob()
        let wait = try JSONObject(validating: Array(#"{"job":"\#(id)","action":"wait","timeout_seconds":60}"#.utf8))
        let tool = JobActionTool(jobs: jobs)
        let context = context
        let waiting = Task { await JobOwner.$current.withValue("thread-1") { await tool.run(wait, in: context) } }
        await jobs.foreground.waitUntilWaiting()
        #expect(!jobs.sendForegroundToBackground(), "main waits on nothing")
        #expect(jobs.sendForegroundToBackground(owner: "thread-1"))
        #expect(await waiting.value.content.contains("the person ended this wait"))
        jobs.job(id)?.stop()
        await jobs.job(id)?.ended()
    }
}
