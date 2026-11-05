import AemiJSON
import AskAI
import AskAgentCore
import Synchronization
import Testing

@testable import AskTools

/// The `agent` tool (roadmap 0063, ADR-0146): the model starts a subagent with its task, what it needs to know and what counts as done,
/// all three required since the subagent sees nothing else; the subagent's summary comes back labelled as its report, data and not
/// instruction; a refusal says why.
@Suite("The model starts a subagent with a task that stands alone")
struct AgentToolTests {
    private func input(_ json: String) throws -> JSONObject { try JSONObject(validating: Array(json.utf8)) }

    private static let whole =
        #"{"task": "Find the flaky test", "context": "Tests/Net, since #12", "done": "name it, with why"}"#

    private func run(_ json: String, answer: SubagentOutcome?) async throws -> (ToolOutput, SubagentTask?) {
        let asked = Mutex<SubagentTask?>(nil)
        var start: SubagentTask.Starter?
        if let answer {
            start = { @Sendable task in
                asked.withLock { $0 = task }
                return answer
            }
        }
        let context = ToolContext(workingDirectory: "/tmp", startSubagent: start)
        let output = await AgentTool().run(try input(json), in: context)
        return (output, asked.withLock { $0 })
    }

    @Test func `the three fields are required in its schema`() {
        let schema = String(decoding: AgentTool().definition.inputSchema.bytes, as: UTF8.self)
        #expect(schema.contains(#""required":["task","context","done"]"#))
    }

    @Test func `the subagent is started on the three, and its summary comes back labelled as its report`() async throws
    {
        let (output, asked) = try await run(
            Self.whole,
            answer: .report(name: "thread-2", summary: "NetRetryTests races the clock.")
        )
        let task = try #require(asked)
        #expect(
            task.task == "Find the flaky test" && task.context == "Tests/Net, since #12"
                && task.done == "name it, with why"
        )
        #expect(
            task.prompt.contains("Find the flaky test") && task.prompt.contains("Tests/Net")
                && task.prompt.contains("with why")
        )
        #expect(!output.isError && output.content.contains("NetRetryTests races the clock."))
        #expect(output.content.hasPrefix("[subagent thread-2's report"), "labelled by origin: data, not instruction")
    }

    @Test func `a missing or empty field is refused by name, before anything starts`() async throws {
        let (output, asked) = try await run(
            #"{"task": "x", "context": "  ", "done": "y"}"#,
            answer: .report(name: "n", summary: "s")
        )
        #expect(output.isError && output.content.contains("context") && asked == nil)
    }

    @Test func `a refusal says why, and with no one to start it the tool says so`() async throws {
        let (refused, _) = try await run(
            Self.whole,
            answer: .refused("4 threads are at work, as many as threads.max allows.")
        )
        #expect(refused.isError && refused.content.contains("threads.max"))
        let (absent, _) = try await run(Self.whole, answer: nil)
        #expect(absent.isError)
    }
}
