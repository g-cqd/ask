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

    private static let reviewer = AgentDefinition.read(
        file: "/u/agents/reviewer.md",
        text: "---\ndescription: Reviews a diff.\ntools: Read\n---\nYou review code carefully."
    )

    @Test func `definitions are named in its description, and only then may a call name one`() throws {
        let reviewer = try #require(Self.reviewer)
        let tool = AgentTool(definitions: [reviewer])
        let schema = String(decoding: tool.definition.inputSchema.bytes, as: UTF8.self)
        #expect(tool.definition.description.contains("reviewer: Reviews a diff.") && schema.contains(#""agent""#))
        #expect(!String(decoding: AgentTool().definition.inputSchema.bytes, as: UTF8.self).contains(#""agent""#))
    }

    @Test func `a named definition goes with the task, its instructions first`() async throws {
        let reviewer = try #require(Self.reviewer)
        let asked = Mutex<SubagentTask?>(nil)
        let context = ToolContext(
            workingDirectory: "/tmp",
            startSubagent: { @Sendable task in
                asked.withLock { $0 = task }
                return .report(name: "thread-1", summary: "ok")
            }
        )
        let json = #"{"task": "t", "context": "c", "done": "d", "agent": "reviewer"}"#
        _ = await AgentTool(definitions: [reviewer]).run(try input(json), in: context)
        let task = try #require(asked.withLock { $0 })
        #expect(task.definition?.name == "reviewer" && task.prompt.hasPrefix("You review code carefully."))
        let unknown = await AgentTool(definitions: [reviewer])
            .run(try input(#"{"task": "t", "context": "c", "done": "d", "agent": "x"}"#), in: context)
        #expect(unknown.isError && unknown.content.contains("reviewer"))
    }
}
