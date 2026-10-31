import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// A model, effort or settings change made while a turn runs applies on the very next request of that turn (roadmap 0113): the
/// running loop takes the loop offered to it before each request, and before a retry, so a person can move off a model that keeps
/// failing without stopping the turn.
@Suite("A change made during a turn applies on its next request")
struct AgentLoopHandoverTests {
    private typealias Provider = ScriptedProvider
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-handover-\(UUID().uuidString)")

    private func session() throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none))
    }

    private func loop(
        _ provider: Provider, model: String, handover: LoopHandover? = nil,
        clock: any Clock<Duration> = ImmediateClock()
    ) throws -> AgentLoop {
        AgentLoop(
            provider: provider, tools: try ToolRegistry([]),
            settings: AgentSettings(model: model, maximumTokens: 64, systemPrompt: ["for \(model)"], maximumTurns: 6),
            context: ToolContext(workingDirectory: directory.path),
            retry: RetryPolicy(
                maximumAttempts: 5, baseDelay: .seconds(60), maximumDelay: .seconds(60),
                maximumRequestedDelay: .seconds(120)),
            clock: clock, handover: handover)
    }

    @Test func `the request after a tool goes to the loop offered while the turn ran`() async throws {
        let before = Provider([.call(id: "c1", name: "missing", input: "{}"), .reply("not this one")])
        let after = Provider([.reply("from the new model")])
        let handover = LoopHandover()
        let running = try loop(before, model: "old", handover: handover)
        let next = try loop(after, model: "new")
        let offered = Mutex(false)
        try await running.run("go", in: try session()) { event in
            if case .responded = event, !offered.withLock({ $0 }) {
                offered.withLock { $0 = true }
                handover.offer(next)
            }
        }
        #expect(before.requests.count == 1)
        #expect(after.requests.count == 1)
        let request = try #require(after.requests.first)
        #expect(
            request.model == "new" && request.systemPrompt == ["for new"],
            "the new loop's settings, its system prompt too")
        #expect(request.messages.count == 3, "the whole turn so far: the prompt, the call, and its result")
    }

    @Test func `a change made while a retry waits ends the wait and sends to the new model`() async throws {
        let before = Provider([.transient(retryAfter: .seconds(60))])
        let after = Provider([.reply("served")])
        let handover = LoopHandover()
        let running = try loop(before, model: "old", handover: handover, clock: ContinuousClock())
        let next = try loop(after, model: "new")
        let started = ContinuousClock.now
        try await running.run("go", in: try session()) { event in
            if case .retrying = event { handover.offer(next) }
        }
        #expect(ContinuousClock.now - started < .seconds(10), "the 60-second wait was not sat out")
        #expect(before.requests.count == 1 && after.requests.count == 1)
    }

    @Test func `a window learned from one model is kept for that model and forgotten for another`() throws {
        let running = try loop(Provider([]), model: "old")
        running.learnedWindow.learn(1_000)
        #expect(running.adopting(try loop(Provider([]), model: "old")).learnedWindow.window == 1_000)
        #expect(running.adopting(try loop(Provider([]), model: "new")).learnedWindow.window == nil)
    }

    @Test func `nothing offered leaves the loop as it was`() async throws {
        let provider = Provider([.reply("ok")])
        try await loop(provider, model: "old", handover: LoopHandover()).run("go", in: try session()) { _ in }
        #expect(provider.requests.map(\.model) == ["old"])
    }
}
