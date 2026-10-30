import Testing

@testable import AskAgentCore

/// The system's path answers, whatever the Mac's network is now, and a wait ends at its limit or when the turn is stopped.
@Suite("The system's network path", .timeLimit(.minutes(1)))
struct SystemNetworkPathTests {
    @Test func `a check answers, and a wait for a route returns by its limit`() async {
        let path = SystemNetworkPath()
        _ = await path.isSatisfied()
        let start = ContinuousClock.now
        _ = await path.waitUntilSatisfied(atMost: .milliseconds(300))
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func `a stopped turn stops waiting`() async {
        let waiting = Task { await SystemNetworkPath().waitUntilSatisfied(atMost: .seconds(600)) }
        waiting.cancel()
        let start = ContinuousClock.now
        _ = await waiting.value
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
