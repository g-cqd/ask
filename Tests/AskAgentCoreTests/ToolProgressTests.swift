import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// Roadmap 0067, phase 4: what a long tool says of how far it has got reaches the reporter the run was given, under the call's id, while
/// the call runs. With no reporter, a tool is told no one is listening, so it asks its server for nothing.
@Suite("A tool's progress reaches the run's reporter under its call's id")
struct ToolProgressTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-progress-\(UUID().uuidString)")

    private struct Reporting: Tool {
        let definition = ToolDefinition(
            name: "long",
            description: "Takes a while.",
            inputSchema: (try? JSONObject(validating: Array(#"{"type":"object"}"#.utf8))) ?? .empty
        )

        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
            context.reportProgress("half way")
            return ToolOutput(context.reportsProgress ? "listened to" : "alone")
        }
    }

    private func run(reporter: ToolProgressReporter?) async throws -> [AgentEvent] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none)
        )
        let loop = AgentLoop(
            provider: ScriptedProvider([.call(id: "c7", name: "long", input: "{}"), .reply("Done.")]),
            tools: try ToolRegistry([Reporting()]),
            settings: AgentSettings(model: "claude-x", maximumTokens: 1_024, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path, progress: reporter)
        )
        var events: [AgentEvent] = []
        try await loop.run("Go", in: file) { events.append($0) }
        return events
    }

    @Test func `a report is told with the id of the call that made it`() async throws {
        let seen = Mutex<[String]>([])
        let events = try await run(reporter: { call, text in seen.withLock { $0.append("\(call): \(text)") } })
        #expect(seen.withLock { $0 } == ["c7: half way"])
        #expect(events.contains(.toolFinished(id: "c7", name: "long", output: ToolOutput("listened to"))))
    }

    @Test func `without a reporter a report goes nowhere and the tool knows no one listens`() async throws {
        let events = try await run(reporter: nil)
        #expect(events.contains(.toolFinished(id: "c7", name: "long", output: ToolOutput("alone"))))
    }

    @Test func `a context outside a call reports nothing, even with a reporter`() {
        let seen = Mutex(0)
        let context = ToolContext(workingDirectory: "/tmp", progress: { _, _ in seen.withLock { $0 += 1 } })
        context.reportProgress("lost")
        #expect(seen.withLock { $0 } == 0 && !context.reportsProgress)
        #expect(context.during(call: "a") != context && context.during(call: "a") == context.during(call: "a"))
    }
}
