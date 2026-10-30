import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// With no network, a failed request waits for it to come back instead of spending its retries in seconds (roadmap 0141): up to a
/// ceiling of minutes, said by the status bar, without counting as an attempt; with the network there, the usual backoff applies.
@Suite("Waiting for the network")
struct AgentLoopNetworkWaitTests {
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-offline-\(UUID().uuidString)")

    private func run(_ provider: ScriptedProvider, network: FakeNetworkPath, attempts: Int = 2) async throws
        -> (AgentError?, [AgentEvent], ImmediateClock)
    {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recorder = SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none))
        let clock = ImmediateClock()
        let loop = AgentLoop(
            provider: provider, tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 8),
            context: ToolContext(workingDirectory: directory.path),
            retry: RetryPolicy(
                maximumAttempts: attempts, baseDelay: .seconds(1), maximumDelay: .seconds(30),
                maximumRequestedDelay: .seconds(120)),
            clock: clock, network: network, networkWait: .seconds(300))
        let events = Mutex<[AgentEvent]>([])
        do throws(AgentError) {
            try await loop.run("go", in: recorder) { event in events.withLock { $0.append(event) } }
            return (nil, events.withLock { $0 }, clock)
        } catch {
            return (error, events.withLock { $0 }, clock)
        }
    }

    private func waited(_ events: [AgentEvent]) -> Int {
        events.filter { if case .waitingForNetwork = $0 { true } else { false } }.count
    }

    @Test func `offline, the request waits for the network and its retries are not spent`() async throws {
        let network = FakeNetworkPath(online: [false, false, false, true])
        let provider = ScriptedProvider([
            .transient(retryAfter: nil), .transient(retryAfter: nil), .transient(retryAfter: nil), .reply("ok")
        ])
        let (error, events, clock) = try await run(provider, network: network, attempts: 2)
        #expect(error == nil, "three failures with two attempts: the waits did not count")
        #expect(waited(events) == 3 && network.waits == [.seconds(300), .seconds(300), .seconds(300)])
        #expect(clock.sleeps.isEmpty, "the network coming back is the signal, not a timer")
        #expect(provider.requests.count == 4)
    }

    @Test func `a network that does not come back ends the turn after the ceiling`() async throws {
        let network = FakeNetworkPath(online: [false], comesBack: false)
        let provider = ScriptedProvider([.transient(retryAfter: nil), .reply("never")])
        let (error, events, _) = try await run(provider, network: network)
        #expect(error == .provider("overloaded"))
        #expect(waited(events) == 1 && provider.requests.count == 1)
    }

    @Test func `online, a failure is retried with the usual backoff, and no wait is said`() async throws {
        let network = FakeNetworkPath(online: [true])
        let provider = ScriptedProvider([.transient(retryAfter: nil), .reply("ok")])
        let (error, events, clock) = try await run(provider, network: network)
        #expect(error == nil && waited(events) == 0 && network.waits.isEmpty)
        #expect(clock.sleeps == [.seconds(1)])
    }

    @Test func `a drop part way waits for the network too, then carries on`() async throws {
        let network = FakeNetworkPath(online: [false, true])
        let provider = ScriptedProvider([.textThenTransient("half"), .reply("rest")])
        let (error, events, _) = try await run(provider, network: network)
        #expect(error == nil && waited(events) == 1)
        #expect(events.contains { if case .continuedAfterDrop = $0 { true } else { false } })
    }

    @Test func `a failure that is not transient never waits`() async throws {
        let network = FakeNetworkPath(online: [false])
        let provider = ScriptedProvider([.permanent])
        let (error, events, _) = try await run(provider, network: network)
        #expect(error == .provider("credential refused") && waited(events) == 0)
    }
}
