import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// Roadmap 0192: a request a hook rewrote is recorded on the response that answered it (which hooks, and the size before and after),
/// not in the conversation, so a resume replays the conversation as it was; the run says so once, however many requests it rewrote.
@Suite("A rewritten request is recorded on its response and said once a run")
struct HookRequestRewriteTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-rewrite-\(UUID().uuidString)")

    private struct Appender: AgentHook {
        let name = "appender"
        func requestBefore(_ request: ModelRequest) async -> RequestBeforeDecision {
            var next = request
            next.systemPrompt.append("EXTRA")
            return .rewrite(next)
        }
    }

    private struct Echo: ArgumentTool {
        struct Arguments: Decodable, Sendable { let text: String }
        let definition = ToolDefinition(name: "echo", description: "Echo.") { ToolProperty.string("text") }
        func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
            ToolOutput(arguments.text)
        }
    }

    private func run(_ hooks: [any AgentHook]) async throws -> (
        path: String, events: [AgentEvent], sent: [ModelRequest]
    ) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "s-\(UUID().uuidString).jsonl").path
        let file = SessionRecorder(try SessionFile.create(at: .init(path), durability: .none))
        let provider = ScriptedProvider([.call(id: "t1", name: "echo", input: #"{"text":"hi"}"#), .reply("Done.")])
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([Echo()]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: ["BASE"], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path),
            hooks: hooks
        )
        let events = Mutex<[AgentEvent]>([])
        try await loop.run("Go", in: file) { event in events.withLock { $0.append(event) } }
        return (path, events.withLock { $0 }, provider.requests)
    }

    private func rewrites(at path: String) throws -> [RequestRewrite?] {
        try SessionFile.open(at: .init(path)).tree.entries
            .compactMap { entry in
                if case .response(_, let rewrite) = entry.payload { rewrite } else { nil }
            }
    }

    @Test func `each rewritten request is kept on its response, read back, while the conversation keeps what it was`()
        async throws
    {
        let outcome = try await run([Appender()])
        #expect(outcome.sent.allSatisfy { $0.systemPrompt == ["BASE", "EXTRA"] }, "the provider saw the rewrite")
        let kept = try rewrites(at: outcome.path)
        #expect(kept.count == 2)
        for rewrite in kept {
            #expect(rewrite?.hooks == ["appender"])
            #expect(rewrite.map { $0.bytesAfter - $0.bytesBefore } == "EXTRA".utf8.count)
        }
    }

    @Test func `the run says once that hooks rewrote its requests`() async throws {
        let said = try await run([Appender()]).events
            .filter { if case .hookRewroteRequest = $0 { true } else { false } }
        #expect(said == [.hookRewroteRequest(hooks: ["appender"])])
    }

    @Test func `without a rewrite nothing is recorded, and the file carries no rewrite key`() async throws {
        let outcome = try await run([])
        #expect(try rewrites(at: outcome.path) == [nil, nil])
        let text = try String(contentsOfFile: outcome.path, encoding: .utf8)
        #expect(!text.contains("\"rewrite\""), "older builds read the same file as before")
        #expect(!outcome.events.contains { if case .hookRewroteRequest = $0 { true } else { false } })
    }
}
