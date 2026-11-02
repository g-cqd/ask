import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// A hook asked when a run would end may send a message and keep it going (roadmap 0192, ADR-0143), within `maximumHookContinues` and
/// the turn limit, after the person's own follow-ups.
@Suite("A hook at the end of a run can continue it, within its limits")
struct AgentHookRunStopTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-runstop-\(UUID().uuidString)")

    /// Answers each end of a run with `answer(continued)`, and keeps the counts it was given.
    private final class Stopper: AgentHook {
        let answer: @Sendable (Int) -> RunStopDecision
        private let seen = Mutex<[Int]>([])
        var asked: [Int] { seen.withLock { $0 } }
        init(_ answer: @escaping @Sendable (Int) -> RunStopDecision) { self.answer = answer }

        func runStop(_ stop: RunStop) async -> RunStopDecision {
            seen.withLock { $0.append(stop.continued) }
            return answer(stop.continued)
        }
    }

    private struct Outcome {
        let users: [String]
        let events: [AgentEvent]
        let requests: Int
    }

    private func run(
        _ hooks: [any AgentHook],
        replies: Int = 6,
        turns: Int = 10,
        continues: Int = 3,
        input: PromptQueue? = nil
    ) async throws -> Outcome {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none)
        )
        let provider = ScriptedProvider((0 ..< replies).map { .reply("Reply \($0).") })
        var settings = AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: turns)
        settings.maximumHookContinues = continues
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([]),
            settings: settings,
            context: ToolContext(workingDirectory: directory.path),
            hooks: hooks
        )
        let events = Mutex<[AgentEvent]>([])
        try await loop.run("Go", in: file, input: input) { event in events.withLock { $0.append(event) } }
        let users = file.tree.entries.compactMap { entry -> String? in
            if case .user(let text) = entry.payload { text } else { nil }
        }
        return Outcome(users: users, events: events.withLock { $0 }, requests: provider.requests.count)
    }

    private func continuedEvents(_ events: [AgentEvent]) -> Int {
        events.filter { if case .hookContinued = $0 { true } else { false } }.count
    }

    private func stopped(_ events: [AgentEvent]) -> [HookContinueLimit] {
        events.compactMap { if case .hookContinuesStopped(let limit) = $0 { limit } else { nil } }
    }

    @Test func `a hook that says stop ends the run as before`() async throws {
        let hook = Stopper { _ in .stop }
        let outcome = try await run([hook])
        #expect(outcome.requests == 1)
        #expect(outcome.users == ["Go"])
        #expect(hook.asked == [0])
        #expect(continuedEvents(outcome.events) == 0)
        #expect(stopped(outcome.events).isEmpty)
    }

    @Test func `a hook that continues sends its message, labelled, and the run goes on`() async throws {
        let hook = Stopper { $0 == 0 ? .continue("Run the tests again.") : .stop }
        let outcome = try await run([hook])
        #expect(outcome.requests == 2)
        #expect(outcome.users == ["Go", "[hook Stopper] Run the tests again."])
        #expect(hook.asked == [0, 1])
        #expect(continuedEvents(outcome.events) == 1)
    }

    @Test func `continues stop at the setting, and the run says so`() async throws {
        let hook = Stopper { _ in .continue("Again.") }
        let outcome = try await run([hook], continues: 2)
        #expect(outcome.requests == 3)
        #expect(hook.asked == [0, 1])
        #expect(stopped(outcome.events) == [.continues(2)])
    }

    @Test func `continues count against the turn limit, and the run ends without an error`() async throws {
        let hook = Stopper { _ in .continue("Again.") }
        let outcome = try await run([hook], turns: 2, continues: 5)
        #expect(outcome.requests == 2)
        #expect(hook.asked == [0])
        #expect(stopped(outcome.events) == [.turns(2)])
    }

    @Test func `several hooks that continue join into one entry, counted once`() async throws {
        let first = Stopper { $0 == 0 ? .continue("One.") : .stop }
        let second = Stopper { $0 == 0 ? .continue("Two.") : .stop }
        let outcome = try await run([first, second], continues: 1)
        #expect(outcome.users == ["Go", "[hook Stopper] One.\n\n[hook Stopper] Two."])
        #expect(outcome.requests == 2)
        #expect(stopped(outcome.events) == [.continues(1)])
    }

    @Test func `the person's follow-up goes first, and the hook is asked only after it`() async throws {
        let hook = Stopper { _ in .stop }
        let input = PromptQueue()
        input.append(QueuedPrompt(id: 1, text: "Later", delivery: .followUp))
        let outcome = try await run([hook], input: input)
        #expect(outcome.users == ["Go", "Later"])
        #expect(hook.asked == [0])
    }

    @Test func `a blank message continues nothing`() async throws {
        let hook = Stopper { _ in .continue(" \n") }
        let outcome = try await run([hook])
        #expect(outcome.requests == 1)
        #expect(outcome.users == ["Go"])
    }

    @Test func `without hooks, no limit is said`() async throws {
        let outcome = try await run([], turns: 1, continues: 0)
        #expect(outcome.requests == 1)
        #expect(stopped(outcome.events).isEmpty)
    }
}
