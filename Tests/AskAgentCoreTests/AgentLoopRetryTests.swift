import AemiIO
import AskAI
import Foundation
import Synchronization
import System
import Testing

@testable import AskAgentCore

/// Transient provider failures are retried with backoff, never after output was shown. Waits go through an
/// immediate clock that records them, so no test can hang on a wait it did not expect.
@Suite("Transient failures are retried with backoff, never after anything was shown")
struct AgentLoopRetryTests {
    private typealias Provider = AgentLoopTests.ScriptedProvider
    private let directory = FileManager.default.temporaryDirectory.appending(path: "ask-retry-\(UUID().uuidString)")

    private func session() throws -> SessionRecorder {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return SessionRecorder(
            try SessionFile.create(at: .init(directory.appending(path: "s.jsonl").path), durability: .none))
    }

    private func loop(_ provider: Provider, clock: ImmediateClock, attempts: Int = 5) throws -> AgentLoop {
        AgentLoop(
            provider: provider, tools: try ToolRegistry([]),
            settings: AgentSettings(model: "m", maximumTokens: 64, systemPrompt: [], maximumTurns: 4),
            context: ToolContext(workingDirectory: directory.path),
            retry: RetryPolicy(
                maximumAttempts: attempts, baseDelay: .seconds(1), maximumDelay: .seconds(30),
                maximumRequestedDelay: .seconds(120)),
            clock: clock)
    }

    /// Runs the loop to its end and returns how it ended and every event.
    private func run(_ loop: AgentLoop) async throws -> (Result<Void, AgentError>, [AgentEvent]) {
        let events = Mutex<[AgentEvent]>([])
        let recorder = try session()
        do throws(AgentError) {
            try await loop.run("go", in: recorder) { event in events.withLock { $0.append(event) } }
            return (.success(()), events.withLock { $0 })
        } catch {
            return (.failure(error), events.withLock { $0 })
        }
    }

    private func failure(_ result: Result<Void, AgentError>) -> AgentError? {
        if case .failure(let error) = result { return error }
        return nil
    }

    private func retries(_ events: [AgentEvent]) -> [(Int, Duration)] {
        events.compactMap {
            if case .retrying(let attempt, _, let delay, _) = $0 { return (attempt, delay) }
            return nil
        }
    }

    @Test func `transient failures are retried with doubling waits, then the reply is used`() async throws {
        let clock = ImmediateClock()
        let provider = Provider([.transient(retryAfter: nil), .transient(retryAfter: nil), .reply("ok")])
        let (result, events) = try await run(try loop(provider, clock: clock))
        #expect((try? result.get()) != nil)
        #expect(retries(events).map(\.0) == [2, 3])
        #expect(retries(events).map(\.1) == [.seconds(1), .seconds(2)])
        #expect(provider.requests.count == 3)
        #expect(clock.sleeps == [.seconds(1), .seconds(2)])
    }

    @Test func `the provider's requested wait wins`() async throws {
        let clock = ImmediateClock()
        let provider = Provider([.transient(retryAfter: .seconds(7)), .reply("ok")])
        let (_, events) = try await run(try loop(provider, clock: clock))
        #expect(retries(events).map(\.1) == [.seconds(7)])
        #expect(clock.sleeps == [.seconds(7)])
    }

    @Test func `after the last attempt the failure ends the run`() async throws {
        let clock = ImmediateClock()
        let provider = Provider([.transient(retryAfter: nil), .transient(retryAfter: nil)])
        let (result, _) = try await run(try loop(provider, clock: clock, attempts: 2))
        #expect(failure(result) == .provider("overloaded"))
        #expect(provider.requests.count == 2)
    }

    @Test func `a failure after text was shown is not retried`() async throws {
        let clock = ImmediateClock()
        let provider = Provider([.textThenTransient("partial"), .reply("ok")])
        let (result, events) = try await run(try loop(provider, clock: clock))
        #expect(failure(result) == .provider("overloaded"))
        #expect(retries(events).isEmpty)
        #expect(provider.requests.count == 1)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func `a failure that is not transient is not retried`() async throws {
        let clock = ImmediateClock()
        let provider = Provider([.failure, .reply("ok")])
        let (result, _) = try await run(try loop(provider, clock: clock))
        #expect(failure(result) == .provider("scripted failure"))
        #expect(provider.requests.count == 1)
    }

    @Test func `a failure the provider says is permanent is not retried`() async throws {
        let clock = ImmediateClock()
        let provider = Provider([.permanent, .reply("ok")])
        let (result, _) = try await run(try loop(provider, clock: clock))
        #expect(failure(result) == .provider("credential refused"))
        #expect(provider.requests.count == 1)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func `the waits double from the base and stop at the cap; requested waits are capped too`() {
        let policy = RetryPolicy.standard
        #expect(
            (1 ... 7).map { policy.delay(after: $0, requested: nil) }
                == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30)])
        #expect(policy.delay(after: 1, requested: .seconds(600)) == .seconds(120))
        #expect(policy.delay(after: 1, requested: .seconds(-5)) == .zero)
    }
}
