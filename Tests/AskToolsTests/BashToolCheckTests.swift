internal import AskAI
internal import AskAgentCore
internal import Testing

@testable import AskTools

/// The check hook's command goes through the `bash` tool (roadmap 0192), and its result is read back: exit 0 passes, another exit fails
/// with what it printed, and a check that timed out, was stopped or could not start did not finish.
@Suite("A check runs as a bash call, and its result is read as passed, failed or unfinished")
struct BashToolCheckTests {
    @Test func `the input names the command and its deadline`() throws {
        let input = try #require(BashTool.checkInput(command: #"swift test --filter "A B""#, seconds: 300))
        #expect(
            String(decoding: input.bytes, as: UTF8.self)
                == #"{"command":"swift test --filter \"A B\"","timeout_seconds":300}"#
        )
    }

    @Test func `exit 0 passes, another exit fails with the output`() {
        #expect(BashTool.checkOutcome(of: ToolOutput("ok\n[exit 0]")) == .passed)
        #expect(BashTool.checkOutcome(of: .error("Test a failed\n[exit 1]")) == .failed("Test a failed\n[exit 1]"))
    }

    @Test func `a check that timed out, was stopped or could not start did not finish`() {
        for output in [
            "partial\n\(BashTool.timedOutMark) 600 s; the command and its children were stopped]",
            "partial\n\(BashTool.abortedMark)",
            "bash could not start: no shell"
        ] {
            #expect(BashTool.checkOutcome(of: .error(output)) == .unfinished, "\(output)")
        }
    }
}
