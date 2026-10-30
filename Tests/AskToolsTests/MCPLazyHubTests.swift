import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// An interactive hub connects its servers on first need (roadmap 0143): nothing is started at launch, so an idle ask holds no server's
/// memory; the first turn connects them and waits, and stopping that turn does not wait for a slow server.
@Suite("The servers connect on first need", .timeLimit(.minutes(1)))
struct MCPLazyHubTests {
    /// The servers the hub made, by name.
    private final class Made: Sendable {
        let fakes = Mutex<[(name: String, fake: FakeMCPServer)]>([])
        var names: [String] { fakes.withLock { $0.map(\.name) } }
        func fake(_ name: String) -> FakeMCPServer? { fakes.withLock { $0.first { $0.name == name }?.fake } }
    }

    private let made = Made()

    /// A hub that waits for its first need; each name in `held` gets a server that never answers `initialize`, made up front so a test
    /// can wait for it.
    private func hub(holding held: [String: FakeMCPServer] = [:]) -> MCPHub {
        for fake in held.values { fake.holdInitialize() }
        return MCPHub(environment: [:], connectsOnFirstNeed: true) { [made] server, _, _ in
            let fake = held[server.name] ?? FakeMCPServer(tools: ["t"])
            made.fakes.withLock { $0.append((server.name, fake)) }
            return fake
        }
    }

    private var started: [String] { made.names }

    @Test func `nothing is started before the first need, and /mcp says when it will be`() async throws {
        let hub = hub()
        hub.apply([MCPServerSetting(name: "a", command: "x"), MCPServerSetting(name: "b", command: "x", enabled: false)]
        )
        hub.apply([MCPServerSetting(name: "c", command: "x"), MCPServerSetting(name: "b", command: "x", enabled: false)]
        )
        await hub.waitUntilSettled()
        #expect(started.isEmpty)
        #expect(hub.status.map(\.state) == [.waiting, .off])
        #expect(hub.isPending)
        #expect(MCPHub.report(hub.status).first == "c: connects with the first message")
    }

    @Test func `connecting starts the latest servers, waits for them, and says the summary`() async throws {
        let hub = hub()
        var notices = hub.notices.makeAsyncIterator()
        hub.apply([MCPServerSetting(name: "a", command: "x")])
        hub.apply([MCPServerSetting(name: "c", command: "x")])
        await hub.connect()
        #expect(started == ["c"])
        #expect(!hub.isPending)
        #expect(try ToolRegistry([], live: hub.live).definitions.map(\.name) == ["mcp__c__t"])
        #expect(await notices.next() == "1 MCP server connected.")
        await hub.connect()
        #expect(started == ["c"], "connecting again starts nothing")
        await hub.stop()
    }

    @Test func `with nothing configured there is nothing to wait for`() async throws {
        let hub = hub()
        hub.apply([MCPServerSetting(name: "b", command: "x", enabled: false)])
        #expect(!hub.isPending)
        await hub.connect()
        #expect(started.isEmpty)
    }

    @Test func `a turn stopped while a server connects stops waiting, and the server goes on connecting`() async throws
    {
        let slow = FakeMCPServer(tools: ["x"])
        let hub = hub(holding: ["slow": slow])
        hub.apply([MCPServerSetting(name: "slow", command: "x")])
        let waiting = Task { _ = await hub.connect() }
        await slow.waitForInitialize()
        waiting.cancel()
        await waiting.value
        #expect(hub.isPending, "still connecting")
        #expect(!slow.isClosed)
        await hub.stop()
    }

    @Test func `a server that does not answer holds the turn only so long, and goes on connecting`() async throws {
        let stuck = FakeMCPServer(tools: ["x"])
        let hub = hub(holding: ["stuck": stuck])
        hub.apply([MCPServerSetting(name: "stuck", command: "x"), MCPServerSetting(name: "quick", command: "x")])
        let start = ContinuousClock.now
        let settled = await hub.connect(waitingAtMost: .milliseconds(200))
        // The stuck server never answers, so without the cap this would never return. The bound is wide: on a CI runner with few
        // cores, the other suites running at once kept the 200 ms timer from a thread for 13.7 s (run 41139622755).
        #expect(!settled && ContinuousClock.now - start < .seconds(30))
        #expect(
            hub.pendingServers.first == "stuck",
            "the quick one may still be finishing under load; the stuck one never does")
        #expect(!stuck.isClosed)
        await hub.stop()
    }

    @Test func `a hub made the usual way still connects at once`() async throws {
        let hub = MCPHub(environment: [:]) { [made] server, _, _ in
            let fake = FakeMCPServer(tools: ["t"])
            made.fakes.withLock { $0.append((server.name, fake)) }
            return fake
        }
        hub.apply([MCPServerSetting(name: "a", command: "x")])
        await hub.waitUntilSettled()
        #expect(started == ["a"])
        await hub.stop()
    }
}
