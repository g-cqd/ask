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

    /// The next ending the table tells of.
    private func nextEnding(_ endings: AsyncStream<JobEnding>) async -> JobEnding? {
        var iterator = endings.makeAsyncIterator()
        return await iterator.next()
    }

    @Test(.timeLimit(.minutes(1)))
    func `a job left running tells its end once, with what it printed`() async throws {
        let endings = jobs.endings()
        let (id, started) = try await leave("sleep 2; echo built-ok")
        #expect(started.contains("you will be told when it ends"))
        let ending = try #require(await nextEnding(endings))
        #expect(ending.id == id && ending.owner == nil)
        #expect(ending.report.contains("which you left running, ended") && ending.report.contains("built-ok"))
        #expect(jobs.job(id)?.claimEndNotice() == false, "told once")
    }

    @Test(.timeLimit(.minutes(1)))
    func `ends the model saw, or asked not to hear of, are not told; the next one is`() async throws {
        let endings = jobs.endings()
        let (waited, _) = try await leave("sleep 2")
        #expect(try await job(waited, "wait").contains("[\(waited) ended]"))
        let (stopped, _) = try await leave("sleep 30")
        _ = try await job(stopped, "stop")
        let (quiet, _) = try await leave("sleep 2")
        #expect(try await job(quiet, "quiet").contains("you will not be told"))
        await jobs.job(quiet)?.ended()
        // The person's own command: its end is theirs.
        let person = await BashTool(jobs: jobs).runForPerson("sleep 6", shell: nil, in: context)
        #expect(person.backgroundJob != nil && !person.content.contains("you will be told"))
        let (told, _) = try await leave("sleep 8; echo last")
        let ending = try #require(await nextEnding(endings))
        #expect(ending.id == told, "the first end told is the last job's: none of the others was")
    }

    @Test(.timeLimit(.minutes(1)))
    func `a thread's job is told under the thread`() async throws {
        let endings = jobs.endings()
        let jobs = jobs
        let context = context
        // Longer than the yield, so it is left running.
        let input = try JSONObject(validating: Array(#"{"command":"sleep 3","yield_seconds":1}"#.utf8))
        let started = await JobOwner.$current.withValue("thread-2") {
            await BashTool(jobs: jobs).run(input, in: context)
        }
        #expect(started.backgroundJob != nil, Comment(rawValue: started.content))
        #expect(await nextEnding(endings)?.owner == "thread-2")
    }
}
