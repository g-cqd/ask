import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// Hooks see every tool call before it runs and every result after, in registration order (ADR-0025).
///
/// They are the seam extensions, approval prompts and sandbox policy attach to; the loop with no hooks behaves as
/// it always did, which the other loop suites already pin.
@Suite("Hooks can block, rewrite and transform tool calls, in order")
struct AgentHookTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-hooks-\(UUID().uuidString)")

    private func newFile() throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none))
    }

    /// Records what it ran, and echoes its text in capitals.
    private final class Recorder: ArgumentTool {
        struct Arguments: Decodable, Sendable { let text: String }
        let definition = ToolDefinition(name: "echo", description: "Echo.") { ToolProperty.string("text") }
        private let seen = Mutex<[String]>([])
        var ran: [String] { seen.withLock { $0 } }

        func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
            seen.withLock { $0.append(arguments.text) }
            return ToolOutput(arguments.text.uppercased())
        }
    }

    /// A hook built from closures, so each test states only the step it cares about.
    private struct Hook: AgentHook {
        var decide: @Sendable (ToolInvocation) -> ToolCallDecision = { _ in .allow }
        var transform: @Sendable (ToolInvocation, ToolOutput) -> ToolOutput = { $1 }

        func toolCall(_ call: ToolInvocation) async -> ToolCallDecision { decide(call) }
        func toolResult(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolOutput { transform(call, output) }
    }

    private func run(_ hooks: [any AgentHook], tool: Recorder) async throws -> [SessionPayload] {
        let file = try newFile()
        let provider = ScriptedProvider([.call(id: "t1", name: "echo", input: #"{"text":"abc"}"#), .reply("Done.")])
        let loop = AgentLoop(
            provider: provider, tools: try ToolRegistry([tool]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path), hooks: hooks)
        try await loop.run("Go", in: file) { _ in }
        return file.tree.entries.map(\.payload)
    }

    private func result(_ payloads: [SessionPayload]) -> (content: String, isError: Bool)? {
        for case .toolResult(_, let content, let isError) in payloads { return (content, isError) }
        return nil
    }

    @Test func `a blocked call does not run, and the model is told why`() async throws {
        let tool = Recorder()
        let payloads = try await run([Hook(decide: { _ in .block(reason: "writes are not allowed here") })], tool: tool)
        #expect(tool.ran.isEmpty)
        let recorded = try #require(result(payloads))
        #expect(recorded.isError)
        #expect(recorded.content.contains("writes are not allowed here"))
    }

    @Test func `a rewritten call runs with the new input`() async throws {
        let tool = Recorder()
        let rewrite = Hook(decide: { _ in .rewrite(try! JSONObject(validating: Array(#"{"text":"xyz"}"#.utf8))) })
        let payloads = try await run([rewrite], tool: tool)
        #expect(tool.ran == ["xyz"])
        #expect(result(payloads)?.content == "XYZ")
    }

    @Test func `a result can be transformed before the model sees it`() async throws {
        let tool = Recorder()
        let payloads = try await run(
            [Hook(transform: { _, output in ToolOutput(output.content + " [checked]") })], tool: tool)
        #expect(result(payloads)?.content == "ABC [checked]")
    }

    @Test func `hooks run in order: a rewrite is what the next hook sees, and the first block wins`() async throws {
        let tool = Recorder()
        let seenBySecond = Mutex<String?>(nil)
        let first = Hook(decide: { _ in .rewrite(try! JSONObject(validating: Array(#"{"text":"rewritten"}"#.utf8))) })
        let second = Hook(decide: { call in
            seenBySecond.withLock { $0 = String(decoding: call.input.bytes, as: UTF8.self) }
            return .block(reason: "second says no")
        })
        let third = Hook(decide: { _ in
            Issue.record("a hook after a block was asked")
            return .allow
        })
        let payloads = try await run([first, second, third], tool: tool)
        #expect(seenBySecond.withLock { $0 } == #"{"text":"rewritten"}"#)
        #expect(tool.ran.isEmpty)
        #expect(result(payloads)?.content.contains("second says no") == true)
    }

    @Test func `result transforms compose in order`() async throws {
        let tool = Recorder()
        let payloads = try await run(
            [Hook(transform: { $1.appending(" 1") }), Hook(transform: { $1.appending(" 2") })], tool: tool)
        #expect(result(payloads)?.content == "ABC 1 2")
    }
}

extension ToolOutput {
    fileprivate func appending(_ text: String) -> ToolOutput { ToolOutput(content + text, isError: isError) }
}
