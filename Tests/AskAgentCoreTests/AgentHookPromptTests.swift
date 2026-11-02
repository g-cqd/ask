import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// A hook sees each message from the person before it enters the conversation, the run's first and the queued ones (roadmap 0192,
/// ADR-0143): it may let it in, block it, rewrite it or add context. What it changed is recorded, so a resume replays it, and said.
@Suite("Hooks let in, block, rewrite or add to the person's messages")
struct AgentHookPromptTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-prompt-\(UUID().uuidString)")

    private struct Hook: AgentHook {
        let name: String
        let answer: @Sendable (String) -> PromptSubmitDecision
        init(_ name: String, _ answer: @escaping @Sendable (String) -> PromptSubmitDecision) {
            self.name = name
            self.answer = answer
        }
        func promptSubmit(_ text: String) async -> PromptSubmitDecision { answer(text) }
    }

    private struct Outcome {
        let users: [String]
        let events: [AgentEvent]
        let requests: Int
        let error: AgentError?
    }

    private func run(_ hooks: [any AgentHook], input: PromptQueue? = nil) async throws -> Outcome {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none)
        )
        let provider = ScriptedProvider([.reply("One."), .reply("Two."), .reply("Three.")])
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 6),
            context: ToolContext(workingDirectory: directory.path),
            hooks: hooks
        )
        let events = Mutex<[AgentEvent]>([])
        var failure: AgentError?
        do { try await loop.run("Go", in: file, input: input) { event in events.withLock { $0.append(event) } } } catch
        {
            failure = error
        }
        let users = file.tree.entries.compactMap { entry -> String? in
            if case .user(let text) = entry.payload { text } else { nil }
        }
        return Outcome(users: users, events: events.withLock { $0 }, requests: provider.requests.count, error: failure)
    }

    private func later() -> PromptQueue {
        let input = PromptQueue()
        input.append(QueuedPrompt(id: 1, text: "Later", delivery: .followUp))
        return input
    }

    @Test func `a rewritten message is recorded as rewritten, and the change is said`() async throws {
        let outcome = try await run([Hook("Spell") { .rewrite($0 + "!") }])
        #expect(outcome.users == ["Go!"])
        #expect(outcome.events.contains(.hookChangedPrompt(hooks: ["Spell"])))
    }

    @Test func `context is recorded after the message, labelled with the hook`() async throws {
        let outcome = try await run([Hook("Git") { _ in .context("The branch is main.") }])
        #expect(outcome.users == ["Go\n\n[hook Git] The branch is main."])
    }

    @Test func `rewrites chain in order, and context joins in order`() async throws {
        let outcome = try await run([
            Hook("A") { .rewrite($0 + " a") }, Hook("B") { .rewrite($0 + " b") }, Hook("C") { _ in .context("c") },
            Hook("D") { _ in .context("d") }
        ])
        #expect(outcome.users == ["Go a b\n\n[hook C] c\n\n[hook D] d"])
        #expect(outcome.events.contains(.hookChangedPrompt(hooks: ["A", "B", "C", "D"])))
    }

    @Test func `a blocked first message is not recorded or sent, and the run says which hook and why`() async throws {
        let outcome = try await run([Hook("A") { .rewrite($0 + " a") }, Hook("Guard") { _ in .block("no secrets") }])
        #expect(outcome.users.isEmpty && outcome.requests == 0)
        #expect(outcome.error == .promptBlocked("The hook Guard blocked this message: no secrets"))
    }

    @Test func `a blocked queued message leaves the queue unrecorded, is said, and the run ends as it would`()
        async throws
    {
        let input = later()
        let outcome = try await run([Hook("Guard") { $0 == "Later" ? .block("not now") : .allow }], input: input)
        #expect(outcome.users == ["Go"] && outcome.requests == 1 && outcome.error == nil)
        #expect(input.remaining.isEmpty)
        #expect(
            outcome.events.contains(
                .promptBlocked(
                    QueuedPrompt(id: 1, text: "Later", delivery: .followUp),
                    reason: "The hook Guard blocked this message: not now"
                )
            )
        )
    }

    @Test func `a queued message is rewritten too, and accepted as sent`() async throws {
        let outcome = try await run([Hook("Spell") { .rewrite($0 + "!") }], input: later())
        #expect(outcome.users == ["Go!", "Later!"])
        #expect(outcome.events.contains(.promptAccepted(QueuedPrompt(id: 1, text: "Later!", delivery: .followUp))))
        #expect(
            outcome.events.filter { $0 == .hookChangedPrompt(hooks: ["Spell"]) }.count == 2,
            "the first message's change and the queued one's"
        )
    }

    @Test func `a blank rewrite or context changes nothing`() async throws {
        let outcome = try await run([Hook("A") { _ in .rewrite("  ") }, Hook("B") { _ in .context("\n") }])
        #expect(outcome.users == ["Go"])
        #expect(!outcome.events.contains { if case .hookChangedPrompt = $0 { true } else { false } })
    }
}
