import AskAI
import AskAgentCore
import AskMCP
import Testing

@testable import AskTools

@Suite("Per-server MCP exposure honors boundaries, modes and allowlists", .timeLimit(.minutes(1)))
struct MCPExposureTests {
    private let world = MCPWorld()

    private func setting(_ fields: String) throws -> MCPServerSetting {
        let file = try ConfigurationFile.parse(Array("{mcp:{s:{command:'x',\(fields)}}}".utf8), path: "c.json")
        return try #require(file.mcp?.servers.first)
    }

    @Test(arguments: [
        ("", 2, false), ("", 3, true),
        ("maxDirectTools:0", 1, true), ("maxDirectTools:2", 2, false),
        ("maxDirectTools:2", 3, true), ("maxDirectTools:5", 3, false),
        ("maxDirectTools:0,mode:'direct'", 3, false),
        ("maxDirectTools:99,mode:'search'", 1, true)
    ])
    func `exposure distinguishes zero exact threshold override and explicit modes`(_ sample: (String, Int, Bool))
        async throws
    {
        let names = (1 ... sample.1).map { "t\($0)" }
        let host = world.host([try setting(sample.0)], ["s": FakeMCPServer(tools: names)], maximumDirectTools: 2)
        host.start()
        await host.waitUntilSettled()
        #expect(
            world.offered.sorted() == (sample.2 ? ["mcp_call", "mcp_search"] : names.map { "mcp__s__\($0)" }).sorted())
        #expect(
            host.status.map(\.state) == [
                sample.2 ? .searchable(tools: sample.1) : .ready(offered: sample.1, of: sample.1)
            ])
        await host.stop()
    }

    @Test(arguments: ["mode:'search'", "mode:'direct'", "maxDirectTools:0"])
    func `an allowlist is never widened by any exposure policy`(_ fields: String) async throws {
        let fake = FakeMCPServer(tools: ["secret", "allowed", "other"])
        let host = world.host([try setting(fields + ",tools:['allowed']")], ["s": fake])
        host.start()
        await host.waitUntilSettled()
        if fields == "mode:'search'" {
            #expect(try await world.call("mcp_search", #"{"query":""}"#).content == "s: allowed")
            #expect(try await world.call("mcp_call", #"{"server":"s","tool":"secret"}"#).isError)
        } else {
            #expect(world.offered == ["mcp__s__allowed"])
        }
        #expect(fake.calls.isEmpty)
        await host.stop()
    }

    @Test(arguments: ["maxDirectTools:-1", "maxDirectTools:1.5", "maxDirectTools:true", "mode:'maybe'"])
    func `invalid exposure settings are rejected rather than silently defaulted`(_ fields: String) {
        #expect(throws: ConfigurationError.self) { try setting(fields) }
    }

    @Test func `browsing does not promote and each search replaces a bounded promoted set`() async throws {
        let names = (1 ... 12).map { "tool\($0)" }
        let host = world.host([try setting("mode:'search'")], ["s": FakeMCPServer(tools: names)])
        host.start()
        await host.waitUntilSettled()
        _ = try await world.call("mcp_search", #"{"query":""}"#)
        #expect(world.offered.sorted() == ["mcp_call", "mcp_search"])
        _ = try await world.call("mcp_search", #"{"query":"tool"}"#)
        #expect(world.offered.filter { $0.hasPrefix("mcp__s__") }.count == 8)
        _ = try await world.call("mcp_search", #"{"query":"tool12"}"#)
        #expect(world.offered.filter { $0.hasPrefix("mcp__s__") } == ["mcp__s__tool12"])
        await host.stop()
        #expect(world.offered.isEmpty)
    }

    @Test func `search promotes matches and a tool-list change withdraws stale promotions`() async throws {
        let fake = FakeMCPServer(tools: ["read", "write"])
        let host = world.host([try setting("mode:'search'")], ["s": fake])
        host.start()
        await host.waitUntilSettled()
        _ = try await world.call("mcp_search", #"{"query":"read"}"#)
        #expect(world.offered.contains("mcp__s__read"))
        #expect(!world.offered.contains("mcp__s__write"))
        #expect(try await world.call("mcp__s__read") == ToolOutput("ran read"))
        let narrowing = SessionNarrowing()
        narrowing.policy = SandboxPolicy(network: .none)
        let restricted = ToolContext(workingDirectory: "/tmp", sandbox: .unrestricted, narrowing: narrowing)
        #expect(try await world.call("mcp__s__read", in: restricted).isError)
        #expect(fake.calls.map(\.name) == ["read"])
        let staleMatches = host.catalog.candidates
        fake.setTools(["write"])
        fake.announceChange()
        await host.waitUntilListed("s", times: 2)
        host.catalog.promote(staleMatches.filter { $0.tool.name == "read" })
        #expect(!world.offered.contains("mcp__s__read"))
        #expect(try await world.call("mcp__s__read").isError)
        await host.stop()
        #expect(world.offered.isEmpty)
    }
}
