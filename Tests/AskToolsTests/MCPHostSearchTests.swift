import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Testing

@testable import AskTools

/// A server with too many tools to list is searched, not listed (ADR-0100): two tools stand in front of every such server, found by words,
/// and the model calls what it found.
@Suite("A large server's tools are reached through a search and a call", .timeLimit(.minutes(1)))
struct MCPHostSearchTests {
    private let world = MCPWorld()
    private let names = (1 ... 5).map { "t\($0)" }

    private func big(limit: Int = 4) -> (MCPHost, FakeMCPServer) {
        let fake = FakeMCPServer(tools: names)
        return (world.host([world.setting("big")], ["big": fake], maximumDirectTools: limit), fake)
    }

    @Test func `a server over the limit with no list offers the two tools, and none of its own`() async throws {
        let (host, _) = big()
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered == ["mcp_search", "mcp_call"])
        #expect(host.status.map(\.state) == [.searchable(tools: 5)])
        await host.stop()
    }

    @Test func `/mcp tells the person, and how to offer the tools whole; startup only counts it`() async throws {
        let (host, _) = big()
        var notices = host.notices.makeAsyncIterator()
        host.start()
        #expect(await notices.next() == "1 MCP server connected.")
        let said = MCPHub.report(host.status).joined(separator: "\n")
        #expect(
            said.contains("big") && said.contains("5 tools") && said.contains("mcp_search")
                && said.contains("mcp.big.tools"))
        await host.stop()
    }

    @Test func `the search finds a tool by its words and shows the arguments it takes`() async throws {
        let (host, _) = big()
        host.start()
        await host.waitUntilSettled()
        let found = try await world.call("mcp_search", #"{"query":"t3"}"#)
        #expect(!found.isError && found.content.contains("big / t3") && found.content.contains("does t3"))
        #expect(found.content.contains(#""properties":{"q":{"type":"string"}}"#), "the schema is what a call needs")
        #expect(!found.content.contains("big / t4"))
        await host.stop()
    }

    @Test func `a search with no words browses the names`() async throws {
        let (host, _) = big()
        host.start()
        await host.waitUntilSettled()
        #expect(try await world.call("mcp_search", #"{"query":""}"#).content == "big: t1, t2, t3, t4, t5")
        await host.stop()
    }

    @Test func `a search that finds nothing says so and how to browse`() async throws {
        let (host, _) = big()
        host.start()
        await host.waitUntilSettled()
        let nothing = try await world.call("mcp_search", #"{"query":"zebra"}"#)
        #expect(
            !nothing.isError && nothing.content.contains("No tool matches") && nothing.content.contains("empty query"))
        await host.stop()
    }

    @Test func `a call reaches the server with the model's arguments and comes back as text`() async throws {
        let (host, fake) = big()
        host.start()
        await host.waitUntilSettled()
        let output = try await world.call("mcp_call", #"{"server":"big","tool":"t3","arguments":{"q":"urlsession"}}"#)
        #expect(output == ToolOutput("ran t3"))
        #expect(fake.calls.map(\.name) == ["t3"] && fake.calls.first?.arguments == #"{"q":"urlsession"}"#)
        await host.stop()
    }

    @Test func `a call with no arguments sends an empty object`() async throws {
        let (host, fake) = big()
        host.start()
        await host.waitUntilSettled()
        _ = try await world.call("mcp_call", #"{"server":"big","tool":"t1"}"#)
        #expect(fake.calls.first?.arguments == "{}")
        await host.stop()
    }

    @Test func `a tool or a server that is not there is an error that points back to the search`() async throws {
        let (host, fake) = big()
        host.start()
        await host.waitUntilSettled()
        let noTool = try await world.call("mcp_call", #"{"server":"big","tool":"nope"}"#)
        let noServer = try await world.call("mcp_call", #"{"server":"ghost","tool":"t1"}"#)
        #expect(noTool.isError && noTool.content.contains("mcp_search"))
        #expect(noServer.isError && noServer.content.contains("big"), "it names the servers there are")
        #expect(fake.calls.isEmpty)
        await host.stop()
    }

    @Test func `arguments that are not an object are refused before anything is sent`() async throws {
        let (host, fake) = big()
        host.start()
        await host.waitUntilSettled()
        for wrong in [#""q=1""#, "[1]", "7", "true", "1.5"] {
            let output = try await world.call("mcp_call", #"{"server":"big","tool":"t1","arguments":\#(wrong)}"#)
            #expect(output.isError && output.content.contains("must be an object"), "\(wrong)")
        }
        #expect(fake.calls.isEmpty)
        await host.stop()
    }

    @Test func `a search with many matches shows the best few and says there are more`() async throws {
        let many = FakeMCPServer(tools: (1 ... 12).map { "tool\($0)" })
        let host = world.host([world.setting("many")], ["many": many], maximumDirectTools: 4)
        host.start()
        await host.waitUntilSettled()
        let found = try await world.call("mcp_search", #"{"query":"tool"}"#)
        #expect(found.content.components(separatedBy: "many / tool").count - 1 == 8)
        #expect(found.content.contains("The best 8"))
        await host.stop()
    }

    @Test func `a server with a list is offered whole and is not searched`() async throws {
        let fake = FakeMCPServer(tools: names)
        let host = world.host([world.setting("big", tools: ["t1"])], ["big": fake], maximumDirectTools: 1)
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered == ["mcp__big__t1"])
        await host.stop()
    }

    @Test func `two large servers share the two tools, and a search can ask for one`() async throws {
        let one = FakeMCPServer(tools: ["alpha1", "alpha2", "alpha3"])
        let two = FakeMCPServer(tools: ["alpha9", "beta2", "beta3"])
        let host = world.host(
            [world.setting("one"), world.setting("two")], ["one": one, "two": two], maximumDirectTools: 2)
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered == ["mcp_search", "mcp_call"])
        let both = try await world.call("mcp_search", #"{"query":"alpha"}"#)
        #expect(both.content.contains("one / alpha1") && both.content.contains("two / alpha9"))
        let only = try await world.call("mcp_search", #"{"query":"alpha","server":"two"}"#)
        #expect(only.content.contains("two / alpha9") && !only.content.contains("one / alpha1"))
        await host.stop()
    }

    @Test func `the tools' description says which servers they reach`() async throws {
        let (host, _) = big()
        host.start()
        await host.waitUntilSettled()
        let registry = try ToolRegistry([], live: world.live)
        let description = registry.definitions.first { $0.name == "mcp_search" }?.description ?? ""
        #expect(description.contains("big (5 tools)"))
        await host.stop()
    }

    @Test func `when the large server goes away the tools go with it`() async throws {
        let (host, fake) = big()
        var notices = host.notices.makeAsyncIterator()
        host.start()
        await host.waitUntilSettled()
        fake.end()
        while let line = await notices.next(), !line.contains("went away") {}
        #expect(world.offered.isEmpty)
        #expect(try await world.call("mcp_search", #"{"query":"t1"}"#).isError)
        await host.stop()
    }

    @Test func `what the server says its tools are now is what is searched`() async throws {
        let (host, fake) = big()
        host.start()
        await host.waitUntilSettled()
        fake.setTools(names + ["zebra"])
        fake.announceChange()
        await host.waitUntilListed("big", times: 2)
        #expect(try await world.call("mcp_search", #"{"query":"zebra"}"#).content.contains("big / zebra"))
        await host.stop()
    }

    @Test func `a server that shrinks to few enough tools is offered whole after all`() async throws {
        let (host, fake) = big()
        host.start()
        await host.waitUntilSettled()
        fake.setTools(["a", "b"])
        fake.announceChange()
        await host.waitUntilListed("big", times: 2)
        #expect(world.offered == ["mcp__big__a", "mcp__big__b"])
        await host.stop()
    }

    @Test func `a call of a narrowed session is refused, as for any server's tool`() async throws {
        let (host, fake) = big()
        host.start()
        await host.waitUntilSettled()
        let narrowing = SessionNarrowing()
        narrowing.policy = SandboxPolicy(network: .none)
        let narrowed = ToolContext(workingDirectory: "/tmp", sandbox: .unrestricted, narrowing: narrowing)
        let output = try await ToolRegistry([], live: world.live)
            .run(
                name: "mcp_call", input: try JSONObject(validating: Array(#"{"server":"big","tool":"t1"}"#.utf8)),
                in: narrowed)
        #expect(output.isError && output.content.contains("sandbox") && fake.calls.isEmpty)
        await host.stop()
    }
}
