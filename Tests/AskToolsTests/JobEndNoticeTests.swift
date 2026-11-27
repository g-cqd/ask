import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// The model is told when a job it left running ends (owner, 2026-11-27), so it may do something else instead of waiting: once, with
/// how it ended and what it printed, under the thread it was started for. An end the model saw itself (a wait, a stop, a status), a
/// job it made quiet, and the person's own commands are not told.
@Suite("A job the model left running tells it when it ends, unless it saw the end")
struct JobEndNoticeTests {
    private let jobs = JobTable(
        environment: ProcessInfo.processInfo.environment.merging(["SHELL": "/bin/bash"]) { _, shell in shell }
    )
    private let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)

    private func leave(_ command: String) async throws -> (id: String, output: String) {
        let input = try JSONObject(validating: Array(#"{"command":"\#(command)","yield_seconds":1}"#.utf8))
        let started = await BashTool(jobs: jobs).run(input, in: context)
        return (try #require(started.backgroundJob), started.content)
    }

    private func job(_ id: String, _ action: String) async throws -> String {
        let input = try JSONObject(
            validating: Array(#"{"job":"\#(id)","action":"\#(action)","timeout_seconds":30}"#.utf8)
        )
        return await JobActionTool(jobs: jobs).run(input, in: context).content
    }

    /// Releases a job blocked on `read _` so it finishes only after the caller is ready.
    private func release(_ id: String) throws { try #require(jobs.job(id)).sendInput("\n", closing: true) }

    /// The next ending the table tells of.
    private func nextEnding(_ endings: AsyncStream<JobEnding>) async -> JobEnding? {
        var iterator = endings.makeAsyncIterator()
        return await iterator.next()
    }

    @Test(.timeLimit(.minutes(1)))
    func `a job left running tells its end once, with what it printed`() async throws {
        let endings = jobs.endings()
        let (id, started) = try await leave("read _; echo built-ok")
        #expect(started.contains("you will be told when it ends"))
        try release(id)
        let ending = try #require(await nextEnding(endings))
        #expect(ending.id == id && ending.owner == nil)
        #expect(ending.report.contains("which you left running, ended") && ending.report.contains("built-ok"))
        #expect(jobs.job(id)?.claimEndNotice() == false, "told once")
    }

    @Test(.timeLimit(.minutes(1)))
    func `ends the model saw, or asked not to hear of, are not told; the next one is`() async throws {
        let endings = jobs.endings()
        let (waited, _) = try await leave("read _; echo waited-ok")
        async let waitResult = job(waited, "wait")
        await jobs.foreground.waitUntilWaiting()
        try release(waited)
        #expect(try await waitResult.contains("[\(waited) ended]"))

        let (stopped, _) = try await leave("sleep 60")
        _ = try await job(stopped, "stop")

        let (quiet, _) = try await leave("read _")
        #expect(try await job(quiet, "quiet").contains("you will not be told"))
        try release(quiet)
        await jobs.job(quiet)?.ended()

        // The person's own command: its end is theirs.
        let person = await BashTool(jobs: jobs).runForPerson("sleep 60", shell: nil, in: context)
        let personID = try #require(person.backgroundJob)
        #expect(!person.content.contains("you will be told"))
        jobs.job(personID)?.stop()
        await jobs.job(personID)?.ended()

        let (told, _) = try await leave("read _; echo last")
        try release(told)
        let ending = try #require(await nextEnding(endings))
        #expect(ending.id == told, "the first end told is the last job's: none of the others was")
    }

    @Test(.timeLimit(.minutes(1)))
    func `a job that already ended before job wait starts is not told a second time`() async throws {
        let endings = jobs.endings()
        let (early, _) = try await leave("read _")
        // Make it quiet first so its own end does not emit before wait; wait on an already-ended job must still mark endReported.
        _ = try await job(early, "quiet")
        try release(early)
        await jobs.job(early)?.ended()
        // Already ended: returns the ended headline via JobWaiting.ended, marking endReported.
        _ = try await job(early, "notify")
        #expect(jobs.job(early)?.claimEndNotice() == false)

        // Direct check of Job.wait(for: nil) fast path when the job already ended before wait() was called.
        let (fast, _) = try await leave("read _")
        _ = try await job(fast, "quiet")
        try release(fast)
        await jobs.job(fast)?.ended()
        jobs.job(fast)?.notifyOnEnd(true)
        _ = await jobs.job(fast)?.wait(for: nil)
        #expect(jobs.job(fast)?.claimEndNotice() == false, "wait(for: nil) on an ended job marks endReported")
        _ = endings
    }

    @Test(.timeLimit(.minutes(1)))
    func `a thread's job is told under the thread`() async throws {
        let endings = jobs.endings()
        let jobs = jobs
        let context = context
        let input = try JSONObject(validating: Array(#"{"command":"read _","yield_seconds":1}"#.utf8))
        let started = await JobOwner.$current.withValue("thread-2") {
            await BashTool(jobs: jobs).run(input, in: context)
        }
        let id = try #require(started.backgroundJob)
        try release(id)
        #expect(await nextEnding(endings)?.owner == "thread-2")
    }
}
