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
            if case .user(let text, _) = entry.payload { text } else { nil }
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

    /// A hook with a bound of its own (a goal, roadmap 0227) is asked past the setting; the others are not.
    private final class Bounded: AgentHook {
        var hasOwnBound: Bool { true }
        private let seen = Mutex(0)
        var asked: Int { seen.withLock { $0 } }
        func runStop(_ stop: RunStop) async -> RunStopDecision {
            let count = seen.withLock { count in
                count += 1
                return count
            }
            return count < 5 ? .continue("More.") : .stop
        }
    }

    @Test func `past the continue setting, only a hook with its own bound is asked`() async throws {
        let bounded = Bounded()
        let other = Stopper { _ in .stop }
        let outcome = try await run([other, bounded], replies: 8, continues: 2)
        #expect(bounded.asked == 5)
        #expect(other.asked == [0, 1])
        #expect(outcome.requests == 5)
        #expect(stopped(outcome.events).isEmpty)
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

    /// Keeps whether each stop it was asked about followed a change.
    private final class Changes: AgentHook {
        private let seen = Mutex<[Bool]>([])
        var changed: [Bool] { seen.withLock { $0 } }
        func runStop(_ stop: RunStop) async -> RunStopDecision {
            seen.withLock { $0.append(stop.changed) }
            return seen.withLock { $0.count } == 1 ? .continue("Again.") : .stop
        }
    }

    @Test(arguments: [
        ("bash", #"{"command":"make"}"#, true), ("write", #"{"path":"a","content":"x"}"#, true),
        ("read", #"{"path":"a"}"#, false)
    ])
    func `a stop says whether the run changed things since the last stop`(call: (String, String, Bool)) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none)
        )
        let provider = ScriptedProvider([
            .call(id: "t1", name: call.0, input: call.1), .reply("Done."), .reply("Still done.")
        ])
        let hook = Changes()
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([CountingTool(call.0)]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 10),
            context: ToolContext(workingDirectory: directory.path),
            hooks: [hook]
        )
        try await loop.run("Go", in: file) { _ in }
        // The second stop follows a continue that changed nothing.
        #expect(hook.changed == [call.2, false])
    }

    @Test func `what an earlier run changed does not count for the next one`() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none)
        )
        let provider = ScriptedProvider([
            .call(id: "t1", name: "bash", input: #"{"command":"make"}"#), .reply("Built."),
            .call(id: "t2", name: "read", input: #"{"path":"a"}"#),
            .reply("Read.")
        ])
        final class Watch: AgentHook {
            let seen = Mutex<[Bool]>([])
            func runStop(_ stop: RunStop) async -> RunStopDecision {
                seen.withLock { $0.append(stop.changed) }
                return .stop
            }
        }
        let watch = Watch()
        let loop = AgentLoop(
            provider: provider,
            tools: try ToolRegistry([CountingTool("bash"), CountingTool("read")]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 10),
            context: ToolContext(workingDirectory: directory.path),
            hooks: [watch]
        )
        try await loop.run("Build", in: file) { _ in }
        try await loop.run("Read", in: file) { _ in }
        #expect(watch.seen.withLock { $0 } == [true, false])
    }

    @Test func `without hooks, no limit is said`() async throws {
        let outcome = try await run([], turns: 1, continues: 0)
        #expect(outcome.requests == 1)
        #expect(stopped(outcome.events).isEmpty)
    }
}
