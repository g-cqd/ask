import Testing

@testable import AskAgentCore

/// The system's path answers, whatever the Mac's network is now, and a wait ends at its limit or when the turn is stopped. That the
/// waits return at all is the assertion: the suite's time limit is the bound, far below the 600-second wait a stop must cut short.
@Suite("The system's network path", .timeLimit(.minutes(1)))
struct SystemNetworkPathTests {
    @Test func `a check answers, and a wait for a route returns by its limit`() async {
        let path = SystemNetworkPath()
        _ = await path.isSatisfied()
        _ = await path.waitUntilSatisfied(atMost: .milliseconds(300))
    }

    @Test func `a stopped turn stops waiting`() async {
        let waiting = Task { await SystemNetworkPath().waitUntilSatisfied(atMost: .seconds(600)) }
        waiting.cancel()
        _ = await waiting.value
    }
}
