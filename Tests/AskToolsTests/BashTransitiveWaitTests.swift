import AskAI
import AskAgentCore
import Foundation
import Testing

@testable import AskTools

@Suite("Bash transitive waiting capabilities", .timeLimit(.minutes(1)))
struct BashTransitiveWaitTests {
    private let context = ToolContext(workingDirectory: "/tmp")
    private let jobs = JobTable()

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `a command that exits before its port opens reports its exit instead of a timeout`() async throws {
        // Refuse an occupied fixture port rather than silently testing a ready server.
        try #require(!PortWait.accepts(65_535))
        let output = await BashTool(jobs: jobs)
            .run(
                input(#"{"command":"exit 7","wait_for_port":65535,"timeout_seconds":10,"shell":"/bin/bash"}"#),
                in: context)
        #expect(output == .error("[exit 7]"))
        #expect(jobs.summaries.isEmpty)
    }

    @Test func `bash wait_for_output waits until string appears and yields background job`() async throws {
        let bash = BashTool(jobs: jobs)
        let output = await bash.run(
            input(
                #"{"command":"echo step1; echo step2_ready; read hold","wait_for_output":"step2_ready","timeout_seconds":5,"shell":"/bin/bash"}"#
            ),
            in: context)
        #expect(!output.isError)
        #expect(output.content.contains("step2_ready"))
        #expect(output.content.contains("still running"))
        #expect(output.backgroundJob != nil)
        await jobs.stopAll()
    }
}
