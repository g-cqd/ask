import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

/// Roadmap 0173: the person sends the command the model is waiting on to the background; the call returns as a yield would, and the
/// command goes on as a job.
@Suite("A running command the person sends to the background becomes a job")
struct ForegroundCommandTests {
    private let jobs = JobTable(
        environment: ProcessInfo.processInfo.environment.merging(["SHELL": "/bin/bash"]) { _, shell in shell }
    )
    private let context = ToolContext(workingDirectory: FileManager.default.temporaryDirectory.path)

    @Test func `the call returns with the job's id, and the command keeps running`() async throws {
        let bash = BashTool(jobs: jobs)
        let input = try JSONObject(validating: Array(#"{"command":"echo started; sleep 30"}"#.utf8))
        async let output = bash.run(input, in: context)
        await jobs.foreground.waitUntilWaiting()
        let sent = jobs.sendForegroundToBackground()
        let result = await output
        #expect(sent)
        // Sent at once, maybe before the command printed: what it printed is the job's, read through it.
        #expect(!result.isError && result.content.contains("sent to the background by the person"))
        let id = try #require(result.backgroundJob)
        #expect(jobs.job(id)?.status == .running)
        jobs.job(id)?.stop()
        await jobs.job(id)?.ended()
    }

    @Test func `with nothing in the foreground there is nothing to send, and a finished command is not held`()
        async throws
    {
        #expect(!jobs.sendForegroundToBackground())
        let result = await BashTool(jobs: jobs)
            .run(try JSONObject(validating: Array(#"{"command":"true"}"#.utf8)), in: context)
        #expect(result.content.hasSuffix("[exit 0]") && !jobs.sendForegroundToBackground())
    }
}
