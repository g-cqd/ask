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
            world.offered.sorted()
                == (sample.2 ? ["dispatch_call", "search_catalog"] : names.map { "mcp__s__\($0)" }).sorted()
        )
        #expect(
            host.status.map(\.state) == [
                sample.2 ? .searchable(tools: sample.1) : .ready(offered: sample.1, of: sample.1)
            ]
        )
        await host.stop()
    }

    @Test(arguments: ["mode:'search'", "mode:'direct'", "maxDirectTools:0"])
    func `an allowlist is never widened by any exposure policy`(_ fields: String) async throws {
        let fake = FakeMCPServer(tools: ["secret", "allowed", "other"])
        let host = world.host([try setting(fields + ",tools:['allowed']")], ["s": fake])
        host.start()
        await host.waitUntilSettled()
        if fields == "mode:'search'" {
            #expect(try await world.call("search_catalog", #"{"query":""}"#).content == "s: allowed")
            #expect(try await world.call("dispatch_call", #"{"server":"s","tool":"secret"}"#).isError)
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

    /// ADR-0163: a tool list that changes costs the next request the provider's cache, so a search adds nothing to it.
    @Test(arguments: ["", "tool", "tool12", "zebra"])
    func `a search leaves the tool list as it was, and what it found is called through dispatch_call`(_ words: String)
        async throws
    {
        let names = (1 ... 12).map { "tool\($0)" }
        let fake = FakeMCPServer(tools: names)
        let host = world.host([try setting("mode:'search'")], ["s": fake])
        host.start()
        await host.waitUntilSettled()
        let before = try ToolRegistry([], live: world.live).definitions
        _ = try await world.call("search_catalog", #"{"query":"\#(words)"}"#)
        #expect(try ToolRegistry([], live: world.live).definitions == before)
        #expect(world.offered == ["search_catalog", "dispatch_call"])
        #expect(try await world.call("mcp__s__tool12").isError && fake.calls.isEmpty, "found is not offered")
        #expect(try await world.call("dispatch_call", #"{"server":"s","tool":"tool12"}"#) == ToolOutput("ran tool12"))
        await host.stop()
        #expect(world.offered.isEmpty)
    }

    @Test func `a tool the server withdrew is no longer called`() async throws {
        let fake = FakeMCPServer(tools: ["read", "write"])
        let host = world.host([try setting("mode:'search'")], ["s": fake])
        host.start()
        await host.waitUntilSettled()
        #expect(try await world.call("dispatch_call", #"{"server":"s","tool":"read"}"#) == ToolOutput("ran read"))
        fake.setTools(["write"])
        fake.announceChange()
        await host.waitUntilListed("s", times: 2)
        #expect(try await world.call("dispatch_call", #"{"server":"s","tool":"read"}"#).isError)
        #expect(fake.calls.map(\.name) == ["read"])
        await host.stop()
    }
}
