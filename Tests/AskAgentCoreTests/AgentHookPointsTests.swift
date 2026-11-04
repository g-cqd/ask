import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// Roadmap 0192: `request.before`, `response.after`, `tool.result` context, `compaction.before` and `compaction.after`, and hook
/// deadlines (fail open vs fail closed).
@Suite("Hooks attach at request, response, tool result, compaction, and enforce deadlines")
struct AgentHookPointsTests {
    private let directory = FileManager.default.temporaryDirectory.appending(
        path: "ask-hook-points-\(UUID().uuidString)"
    )

    private func newFile() throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionRecorder(
            try SessionFile.create(
                at: .init(directory.appending(path: "s-\(UUID().uuidString).jsonl").path),
                durability: .none
            )
        )
    }

    private final class EchoTool: ArgumentTool {
        struct Arguments: Decodable, Sendable { let text: String }
        let definition = ToolDefinition(name: "echo", description: "Echo.") { ToolProperty.string("text") }
        func run(_ arguments: Arguments, in context: ToolContext) async throws(ToolFailure) -> ToolOutput {
            ToolOutput(arguments.text)
        }
    }

    private final class RequestHook: AgentHook {
        let name = "trimmer"
        let seenResponses = Mutex<[String]>([])

        func requestBefore(_ request: ModelRequest) async -> RequestBeforeDecision {
            var next = request
            next.systemPrompt.append("EXTRA-SYSTEM")
            return .rewrite(next)
        }

        func responseAfter(_ response: AssembledResponse) async {
            seenResponses.withLock { $0.append(response.id) }
        }
    }

    @Test func `requestBefore rewrites the request sent to the provider and responseAfter sees the recorded reply`()
        async throws
    {
        let file = try newFile()
        let provider = ScriptedProvider([.reply("Answered.")])
        let hook = RequestHook()
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: ["BASE"], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path),
            hooks: [hook]
        )
        let events = Mutex<[AgentEvent]>([])
        try await loop.run("Hello", in: file) { event in events.withLock { $0.append(event) } }
        #expect(provider.requests.first?.systemPrompt == ["BASE", "EXTRA-SYSTEM"])
        #expect(events.withLock { $0 }.contains(.hookRewroteRequest(hooks: ["trimmer"])))
        #expect(!hook.seenResponses.withLock { $0 }.isEmpty)
    }

    private struct ResultContextHook: AgentHook {
        let name = "auditor"
        func toolResultDecision(_ call: ToolInvocation, _ output: ToolOutput) async -> ToolResultDecision {
            ToolResultDecision(output: ToolOutput(output.content + "!"), context: "checked \(call.name)")
        }
    }

    @Test func `toolResultDecision transforms output and appends labelled context to the conversation`() async throws {
        let file = try newFile()
        let provider = ScriptedProvider([.call(id: "t1", name: "echo", input: #"{"text":"hi"}"#), .reply("Done.")])
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([EchoTool()]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path),
            hooks: [ResultContextHook()]
        )
        let events = Mutex<[AgentEvent]>([])
        try await loop.run("Go", in: file) { event in events.withLock { $0.append(event) } }
        let users = file.tree.entries.compactMap { entry -> String? in
            if case .user(let text) = entry.payload { text } else { nil }
        }
        #expect(users == ["Go", "[hook auditor] checked echo"])
        #expect(events.withLock { $0 }.contains(.hookAddedContext("[hook auditor] checked echo")))
    }

    private final class CompactionHook: AgentHook {
        let name = "compactor"
        let summaries = Mutex<[String]>([])
        func compactionBefore(entries: [SessionEntry]) async -> CompactionBeforeDecision {
            .instructions("Keep all file paths.")
        }
        func compactionAfter(summary: String, usage: TokenUsage) async {
            summaries.withLock { $0.append(summary) }
        }
    }

    @Test func `compactionBefore adds instructions to the summary prompt and compactionAfter receives the summary`()
        async throws
    {
        let file = try newFile()
        try file.append(.user(String(repeating: "a ", count: 200)))
        try file.append(
            .response(
                AssembledResponse(
                    id: "r1",
                    model: "m",
                    blocks: [.text(String(repeating: "b ", count: 200))],
                    stopReason: .endTurn,
                    usage: TokenUsage(),
                    unrecognized: []
                )
            )
        )
        try file.append(.user("recent"))
        let provider = ScriptedProvider([.reply("Short summary.")])
        let hook = CompactionHook()
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([]),
            settings: AgentSettings(
                model: "m",
                maximumTokens: 64,
                systemPrompt: [],
                maximumTurns: 4,
                keepRecentBytes: 10
            ),
            context: ToolContext(workingDirectory: directory.path),
            hooks: [hook]
        )
        try await loop.compactNow(in: file) { _ in }
        let lastMessage = provider.requests.first?.messages.last
        let sentText =
            lastMessage?.blocks.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: "\n")
            ?? ""
        #expect(sentText.contains("Keep all file paths."))
        #expect(hook.summaries.withLock { $0 } == ["Short summary."])
    }

    private final class SlowHook: AgentHook {
        let name = "slow"
        let deadline: Duration? = .seconds(1)
        let failureMode: HookFailureMode
        let saved = Mutex<CheckedContinuation<Void, Never>?>(nil)

        init(failureMode: HookFailureMode) { self.failureMode = failureMode }

        func promptSubmit(_ text: String) async -> PromptSubmitDecision {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let resumeNow = saved.withLock { box -> CheckedContinuation<Void, Never>? in
                        if Task.isCancelled { return continuation }
                        box = continuation
                        return nil
                    }
                    resumeNow?.resume()
                }
            } onCancel: {
                let pending = saved.withLock { box -> CheckedContinuation<Void, Never>? in
                    defer { box = nil }
                    return box
                }
                pending?.resume()
            }
            return .rewrite("never reached")
        }
    }

    @Test func `a hook past its deadline fails open when configured open, and fails closed when configured closed`()
        async throws
    {
        let file = try newFile()
        let provider = ScriptedProvider([.reply("OK.")])
        let openLoop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path),
            clock: ImmediateClock(),
            hooks: [SlowHook(failureMode: .open)]
        )
        let events = Mutex<[AgentEvent]>([])
        try await openLoop.run("Hello", in: file) { event in events.withLock { $0.append(event) } }
        #expect(events.withLock { $0 }.contains(.hookTimedOut(hook: "slow", point: "prompt.submit")))

        let closedFile = try newFile()
        let closedLoop = AgentLoop(
            provider: ScriptedProvider([.reply("OK.")]),
            tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path),
            clock: ImmediateClock(),
            hooks: [SlowHook(failureMode: .closed)]
        )
        await #expect(throws: AgentError.promptBlocked("The hook slow blocked this message: timed out")) {
            try await closedLoop.run("Hello", in: closedFile) { _ in }
        }
    }
}
