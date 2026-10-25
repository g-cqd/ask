import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Synchronization
import Testing

@testable import AskTools

/// The hub is what outlives the loop (ADR-0099): the loop is rebuilt whenever the configuration changes, and a server must not be started
/// again each time. It follows the configuration, and starts or stops only the servers that changed.
@Suite("The hub keeps the servers across rebuilds, and follows the configuration", .timeLimit(.minutes(1)))
struct MCPHubTests {
    private final class Factory: Sendable {
        private let state = Mutex<(made: [String], fakes: [String: FakeMCPServer])>(([], [:]))
        var made: [String] { state.withLock { $0.made } }
        func fake(_ name: String) -> FakeMCPServer? { state.withLock { $0.fakes[name] } }
        func make(_ server: MCPServerSetting) -> FakeMCPServer {
            state.withLock { state in
                state.made.append(server.command ?? "")
                let fake = FakeMCPServer(tools: [server.command ?? "t"])
                state.fakes[server.name + (server.command ?? "")] = fake
                return fake
            }
        }
    }

    private func hub(_ factory: Factory) -> MCPHub {
        MCPHub(environment: [:], transport: { server, _, _ in factory.make(server) })
    }

    private func names(_ hub: MCPHub) throws -> [String] {
        try ToolRegistry([], live: hub.live).definitions.map(\.name)
    }

    @Test func `nothing configured starts nothing`() async throws {
        let factory = Factory()
        let hub = hub(factory)
        hub.apply([])
        await hub.waitUntilSettled()
        #expect(factory.made.isEmpty && hub.status.isEmpty)
    }

    @Test func `the same servers applied again are not started again`() async throws {
        let factory = Factory()
        let hub = hub(factory)
        let servers = [MCPServerSetting(name: "a", command: "one")]
        hub.apply(servers)
        await hub.waitUntilSettled()
        hub.apply(servers)
        hub.apply(servers)
        await hub.waitUntilSettled()
        #expect(factory.made == ["one"])
        #expect(try names(hub) == ["mcp__a__one"])
        await hub.stop()
    }

    @Test func `a changed configuration stops the old servers and starts the new`() async throws {
        let factory = Factory()
        let hub = hub(factory)
        hub.apply([MCPServerSetting(name: "a", command: "one")])
        await hub.waitUntilSettled()
        hub.apply([MCPServerSetting(name: "a", command: "two")])
        await hub.waitUntilSettled()
        #expect(factory.made == ["one", "two"])
        #expect(factory.fake("aone")?.isClosed == true, "the old one is not left running")
        #expect(try names(hub) == ["mcp__a__two"])
        await hub.stop()
    }

    @Test func `removing every server stops them all`() async throws {
        let factory = Factory()
        let hub = hub(factory)
        hub.apply([MCPServerSetting(name: "a", command: "one")])
        await hub.waitUntilSettled()
        hub.apply([])
        await hub.waitUntilSettled()
        #expect(factory.fake("aone")?.isClosed == true && hub.status.isEmpty)
        #expect(try names(hub).isEmpty)
    }

    @Test func `what the host says is what the hub says, across a change`() async throws {
        let factory = Factory()
        let hub = hub(factory)
        var notices = hub.notices.makeAsyncIterator()
        hub.apply([MCPServerSetting(name: "a", command: "one")])
        #expect(await notices.next()?.contains("MCP server a connected") == true)
        hub.apply([MCPServerSetting(name: "b", command: "two")])
        #expect(await notices.next()?.contains("MCP server b connected") == true)
        await hub.stop()
    }

    @Test func `stopping right after a change leaves nothing of the old servers running`() async throws {
        let factory = Factory()
        let hub = hub(factory)
        hub.apply([MCPServerSetting(name: "a", command: "one")])
        await hub.waitUntilSettled()
        hub.apply([MCPServerSetting(name: "b", command: "two")])
        await hub.stop()
        #expect(factory.fake("aone")?.isClosed == true)
        #expect(factory.fake("btwo")?.isClosed != false, "the new one is closed too, or was never started")
    }

    @Test func `stopping the hub stops the servers and ends its notices`() async throws {
        let factory = Factory()
        let hub = hub(factory)
        hub.apply([MCPServerSetting(name: "a", command: "one")])
        await hub.waitUntilSettled()
        await hub.stop()
        #expect(factory.fake("aone")?.isClosed == true)
        var notices = hub.notices.makeAsyncIterator()
        while await notices.next() != nil {}
    }
}
