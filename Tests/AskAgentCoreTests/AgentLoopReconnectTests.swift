import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// An answer whose connection drops after some of it was shown is carried on (roadmap 0141): what arrived is kept as the answer so far,
/// the model is asked to continue from where it stopped, and nothing incomplete (reasoning, a half-sent tool call) is sent back.
@Suite("A dropped answer is carried on")
struct AgentLoopReconnectTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-reconnect-\(UUID().uuidString)")

    private func loop(_ provider: ScriptedProvider, clock: ImmediateClock, attempts: Int = 5) throws
        -> (AgentLoop, SessionRecorder)
    {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recorder = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none))
        let loop = AgentLoop(
            provider: provider, tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 8),
            context: ToolContext(workingDirectory: directory.path),
            retry: RetryPolicy(
                maximumAttempts: attempts, baseDelay: .seconds(1), maximumDelay: .seconds(30),
                maximumRequestedDelay: .seconds(120)),
            clock: clock)
        return (loop, recorder)
    }

    private func run(_ loop: AgentLoop, in recorder: SessionRecorder) async -> (AgentError?, [AgentEvent]) {
        let events = Mutex<[AgentEvent]>([])
        do throws(AgentError) {
            try await loop.run("go", in: recorder) { event in events.withLock { $0.append(event) } }
            return (nil, events.withLock { $0 })
        } catch {
            return (error, events.withLock { $0 })
        }
    }

    @Test func `text shown before the drop is kept, and the model is asked to carry on`() async throws {
        let clock = ImmediateClock()
        let provider = ScriptedProvider([.textThenTransient("The first half"), .reply(" and the rest.")])
        let (loop, recorder) = try loop(provider, clock: clock)
        let (error, events) = await run(loop, in: recorder)
        #expect(error == nil)
        #expect(provider.requests.count == 2)
        let sent = provider.requests[1].messages.suffix(2)
        #expect(sent.first?.role == .assistant && sent.first?.blocks == [.text("The first half")])
        #expect(sent.last?.role == .user && sent.last?.blocks == [.text(AgentLoop.reconnectionPrompt)])
        #expect(
            events.contains { if case .retrying = $0 { true } else { false } }, "the status says it is reconnecting")
        #expect(events.contains { if case .continuedAfterDrop = $0 { true } else { false } })
        #expect(clock.sleeps == [.seconds(1)])
    }

    @Test func `an answer that just stops before its end is a dropped connection too`() async throws {
        let provider = ScriptedProvider([.textThenEnds("The first half"), .reply(" and the rest.")])
        let (loop, recorder) = try loop(provider, clock: ImmediateClock())
        let (error, events) = await run(loop, in: recorder)
        #expect(error == nil)
        #expect(provider.requests.count == 2)
        #expect(provider.requests[1].messages.suffix(2).first?.blocks == [.text("The first half")])
        #expect(events.contains { if case .continuedAfterDrop = $0 { true } else { false } })
    }

    @Test func `reasoning and a half-sent tool call are never sent back`() async throws {
        let provider = ScriptedProvider([.textAndCutCallThenTransient("Let me look."), .reply("done")])
        let (loop, recorder) = try loop(provider, clock: ImmediateClock())
        let (error, _) = await run(loop, in: recorder)
        #expect(error == nil)
        let kept = provider.requests[1].messages.suffix(2).first
        #expect(kept?.role == .assistant && kept?.blocks == [.text("Let me look.")])
    }

    @Test func `with only reasoning shown, the request is simply sent again`() async throws {
        let provider = ScriptedProvider([.thinkingThenTransient("hmm"), .reply("ok")])
        let (loop, recorder) = try loop(provider, clock: ImmediateClock())
        let (error, events) = await run(loop, in: recorder)
        #expect(error == nil)
        #expect(provider.requests[1].messages == provider.requests[0].messages)
        #expect(!events.contains { if case .continuedAfterDrop = $0 { true } else { false } })
    }

    @Test func `a connection that keeps dropping ends the run after the policy's attempts`() async throws {
        let provider = ScriptedProvider([
            .textThenTransient("a"), .textThenTransient("b"), .textThenTransient("c"), .reply("never")
        ])
        let (loop, recorder) = try loop(provider, clock: ImmediateClock(), attempts: 3)
        let (error, _) = await run(loop, in: recorder)
        #expect(error == .provider("overloaded"))
        #expect(provider.requests.count == 3)
    }

    @Test func `a resumed session shows the carrying on, not the prompt`() async throws {
        let provider = ScriptedProvider([.textThenTransient("half"), .reply("rest")])
        let (loop, recorder) = try loop(provider, clock: ImmediateClock())
        _ = await run(loop, in: recorder)
        let replay = SessionReplay.steps(recorder.tree.context())
        #expect(replay.contains { if case .event(.continuedAfterDrop) = $0 { true } else { false } })
        #expect(
            !replay.contains { if case .prompt(let text) = $0 { text == AgentLoop.reconnectionPrompt } else { false } })
    }
}
