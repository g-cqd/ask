import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// The headless loop over a scripted provider: turns, tools, persistence, limits and abort.
@Suite("The agent loop runs turns and tools, records each as it happens, and stops cleanly")
struct AgentLoopTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-loop-\(UUID().uuidString)")
    private func newFile() throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none))
    }

    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    private func loop(_ provider: ScriptedProvider, tools: [any Tool] = [Upper()], maximumTurns: Int = 8) throws
        -> AgentLoop
    {
        AgentLoop(
            provider: provider, tools: try ToolRegistry(tools),
            settings: AgentSettings(
                model: "claude-x", maximumTokens: 1_024, systemPrompt: ["Be brief."], maximumTurns: maximumTurns),
            context: ToolContext(workingDirectory: directory.path))
    }

    @Test func `a reply without tool calls ends the run after one turn`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.reply("Hello.")])
        var events: [AgentEvent] = []
        try await loop(provider).run("Hi", in: file) { events.append($0) }
        #expect(file.tree.entries.map(\.payload).count == 2)
        guard case .user("Hi") = file.tree.entries[0].payload,
            case .response(let response) = file.tree.entries[1].payload
        else {
            Issue.record("unexpected entries: \(file.tree.entries)")
            return
        }
        #expect(response.blocks == [.text("Hello.")])
        #expect(events.contains(.model(.textDelta(index: 0, "Hello."))))
        #expect(events.last == .finished(.endTurn))
        #expect(provider.requests.count == 1)
        #expect(provider.requests[0].messages == [ModelMessage(role: .user, blocks: [.text("Hi")])])
        #expect(provider.requests[0].systemPrompt == ["Be brief."])
        #expect(provider.requests[0].tools.map(\.name) == ["upper"])
    }

    @Test func `a tool call runs, its result is recorded, and the model sees it next turn`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([
            .call(id: "t1", name: "upper", input: #"{"text":"abc"}"#), .reply("It is ABC.")
        ])
        var events: [AgentEvent] = []
        try await loop(provider).run("Shout abc", in: file) { events.append($0) }
        let payloads = file.tree.entries.map(\.payload)
        #expect(payloads.count == 4)
        #expect(payloads[2] == .toolResult(callID: "t1", content: "ABC", isError: false))
        #expect(provider.requests.count == 2)
        #expect(
            provider.requests[1].messages.last
                == ModelMessage(role: .user, blocks: [.toolResult(id: "t1", content: "ABC", isError: false)]))
        #expect(events.contains(.toolStarted(id: "t1", name: "upper", input: input(#"{"text":"abc"}"#))))
        #expect(events.contains(.toolFinished(id: "t1", name: "upper", output: ToolOutput("ABC"))))
    }

    @Test func `a paused turn is continued, not taken as the end`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.pause("Working…"), .reply("Done.")])
        var events: [AgentEvent] = []
        try await loop(provider).run("Go", in: file) { events.append($0) }
        #expect(provider.requests.count == 2)
        #expect(events.last == .finished(.endTurn))
    }

    @Test func `a response cut off at the output limit is continued, and the continuation is recorded`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.cutOff("The first half"), .reply(" and the rest.")])
        var events: [AgentEvent] = []
        try await loop(provider).run("Write a lot", in: file) { events.append($0) }
        let payloads = file.tree.entries.map(\.payload)
        #expect(payloads.count == 4)
        #expect(payloads[2] == .user(AgentLoop.continuationPrompt))
        #expect(provider.requests.count == 2)
        #expect(
            provider.requests[1].messages.last
                == ModelMessage(role: .user, blocks: [.text(AgentLoop.continuationPrompt)]))
        #expect(events.last == .finished(.endTurn))
    }

    @Test func `an unknown tool becomes an error result and the run continues`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.call(id: "t1", name: "rm", input: "{}"), .reply("Sorry.")])
        try await loop(provider).run("Delete it", in: file) { _ in }
        guard case .toolResult("t1", let content, true) = file.tree.entries[2].payload else {
            Issue.record("expected an error result, got \(file.tree.entries[2].payload)")
            return
        }
        #expect(content.contains("No tool is named rm"))
        #expect(provider.requests.count == 2)
    }

    @Test func `a provider failure ends the run and records no partial response`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.failure])
        await #expect(throws: AgentError.provider("scripted failure")) {
            try await loop(provider).run("Hi", in: file) { _ in }
        }
        #expect(file.tree.entries.map(\.payload) == [.user("Hi")])
    }

    @Test func `the turn limit stops a model that never stops calling tools`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider(
            Array(repeating: .call(id: "t", name: "upper", input: #"{"text":"a"}"#), count: 5))
        await #expect(throws: AgentError.turnLimit(3)) {
            try await loop(provider, maximumTurns: 3).run("Loop", in: file) { _ in }
        }
        #expect(provider.requests.count == 3)
    }

    @Test func `abort between tools records the finished result and leaves the rest unanswered`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.calls([("a", "abort", "{}"), ("b", "upper", #"{"text":"x"}"#)])])
        await #expect(throws: AgentError.cancelled) {
            try await loop(provider, tools: [Upper(), AbortingTool()]).run("Go", in: file) { _ in }
        }
        let payloads = file.tree.entries.map(\.payload)
        #expect(payloads.last == .toolResult(callID: "a", content: "stopping", isError: false))
        let next = RequestContext(file.tree.context())
        #expect(next.repairs == [.interruptedToolCall(id: "b")])
    }

    private struct Upper: ArgumentTool {
        struct Arguments: Decodable, Sendable { let text: String }
        let definition = ToolDefinition(
            name: "upper", description: "Uppercase text.",
            inputSchema: try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8)))

        func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
            ToolOutput(arguments.text.uppercased())
        }
    }

    /// Cancels the task running the loop, as an abort would, and still returns its result.
    private struct AbortingTool: Tool {
        let definition = ToolDefinition(
            name: "abort", description: "Abort.",
            inputSchema: try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8)))

        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
            withUnsafeCurrentTask { $0?.cancel() }
            return ToolOutput("stopping")
        }
    }
}
