import AskAgentCore
import Testing

@testable import AskTools

/// MCP startup says one block for every server (roadmap 0145): how many connected, and which failed and why. Each server's details stay
/// in `/mcp`.
@Suite("MCP startup is summarised in one block")
struct MCPStartupSummaryTests {
    private let world = MCPWorld()

    private func status(_ name: String, _ state: MCPServerStatus.State) -> MCPServerStatus {
        MCPServerStatus(name: name, state: state)
    }

    /// Everything the host said, once it has stopped.
    private func said(by host: MCPHost) async -> [String] {
        await host.stop()
        var lines: [String] = []
        for await line in host.notices { lines.append(line) }
        return lines
    }

    @Test func `the summary counts the connected servers, and lists each failure with its reason`() {
        let ready = MCPServerStatus.State.ready(offered: 2, of: 2)
        #expect(
            MCPStartupSummary.text([
                status("a", ready), status("b", .searchable(tools: 229)), status("c", ready), status("d", ready)
            ]) == "4 MCP servers connected.")
        #expect(
            MCPStartupSummary.text([status("a", ready), status("b", .failed("boom")), status("c", .off)])
                == "1 MCP server connected. 1 failed to connect:\n  b: boom")
        #expect(
            MCPStartupSummary.text([status("a", .failed("x")), status("b", .failed("y"))])
                == "No MCP server connected. 2 failed to connect:\n  a: x\n  b: y")
    }

    @Test func `nothing is said with no server, only servers that are off, or one still connecting`() {
        #expect(MCPStartupSummary.text([]) == nil)
        #expect(MCPStartupSummary.text([status("a", .off)]) == nil)
        #expect(MCPStartupSummary.text([status("a", .ready(offered: 1, of: 1)), status("b", .connecting)]) == nil)
    }

    @Test func `a host says one block once every server has settled, and no line per server`() async throws {
        let bad = FakeMCPServer()
        bad.refuseInitialize()
        let host = world.host(
            [world.setting("a"), world.setting("bad"), world.setting("big"), world.setting("off", enabled: false)],
            ["a": FakeMCPServer(tools: ["x"]), "bad": bad, "big": FakeMCPServer(tools: (1 ... 300).map { "t\($0)" })])
        host.start()
        await host.waitUntilSettled()
        let lines = await said(by: host)
        #expect(lines.count == 1, "\(lines)")
        #expect(lines.first?.hasPrefix("2 MCP servers connected. 1 failed to connect:\n  bad: ") == true)
    }

    @Test func `nothing is declared while a server is still connecting`() async throws {
        let slow = FakeMCPServer(tools: ["x"])
        slow.holdInitialize()
        let host = world.host(
            [world.setting("fast"), world.setting("slow")], ["fast": FakeMCPServer(tools: ["y"]), "slow": slow])
        host.start()
        await host.waitUntilListed("fast", times: 1)
        await slow.waitForInitialize()
        #expect(await said(by: host).isEmpty)
    }

    @Test func `no servers, or only servers that are off, say nothing`() async throws {
        let host = world.host([world.setting("off", enabled: false)], [:])
        host.start()
        await host.waitUntilSettled()
        #expect(await said(by: host).isEmpty)
    }
}
