import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Testing

@testable import AskTools

/// The host connects the configured servers in the background and offers their tools (ADR-0099): nothing waits for a server to start, a
/// server that fails costs only itself, and what a server offers follows what it says.
@Suite("Servers connect on their own, and their tools come and go with them", .timeLimit(.minutes(1)))
struct MCPHostTests {
    private let world = MCPWorld()

    @Test func `a server's tools are world.offered under its name once it has connected`() async throws {
        let host = world.host([world.setting("srv")], ["srv": FakeMCPServer(tools: ["search", "read"])])
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered == ["mcp__srv__search", "mcp__srv__read"])
        #expect(host.status.map(\.state) == [.ready(offered: 2, of: 2)])
        await host.stop()
    }

    @Test func `starting does not wait: the tools are not there until the server has answered`() async throws {
        let host = world.host([world.setting("srv")], ["srv": FakeMCPServer(tools: ["a"])])
        host.start()
        #expect(host.status.map(\.state) == [.connecting] || host.status.map(\.state) == [.ready(offered: 1, of: 1)])
        await host.waitUntilSettled()
        await host.stop()
    }

    @Test func `a server that is off is not connected`() async throws {
        let fake = FakeMCPServer(tools: ["a"])
        let host = world.host([world.setting("srv", enabled: false)], ["srv": fake])
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered.isEmpty && host.status.map(\.state) == [.off])
        #expect(fake.listings == 0)
    }

    @Test func `a list of tools offers those, and says which it asked for that the server lacks`() async throws {
        let host = world.host(
            [world.setting("srv", tools: ["b", "nope"])], ["srv": FakeMCPServer(tools: ["a", "b", "c"])])
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered == ["mcp__srv__b"])
        #expect(host.status.map(\.state) == [.ready(offered: 1, of: 3)])
        #expect(host.status[0].notes.contains { $0.contains("nope") })
        await host.stop()
    }

    @Test func `a server with exactly as many tools as the limit is world.offered whole`() async throws {
        let names = (1 ... 4).map { "t\($0)" }
        let host = world.host([world.setting("edge")], ["edge": FakeMCPServer(tools: names)], maximumDirectTools: 4)
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered.count == 4 && host.status.map(\.state) == [.ready(offered: 4, of: 4)])
        await host.stop()
    }

    @Test func `a list lets a big server in, even past the limit`() async throws {
        let names = (1 ... 5).map { "t\($0)" }
        let host = world.host(
            [world.setting("big", tools: ["t1", "t2"])], ["big": FakeMCPServer(tools: names)], maximumDirectTools: 1)
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered == ["mcp__big__t1", "mcp__big__t2"])
        await host.stop()
    }

    @Test func `a server that refuses to start costs only itself, and its reason is kept`() async throws {
        let bad = FakeMCPServer()
        bad.refuseInitialize()
        let host = world.host(
            [world.setting("bad"), world.setting("good")], ["bad": bad, "good": FakeMCPServer(tools: ["a"])])
        host.start()
        await host.waitUntilSettled()
        #expect(world.offered == ["mcp__good__a"])
        guard case .failed(let reason) = host.status.first(where: { $0.name == "bad" })?.state else {
            Issue.record("bad did not fail")
            return
        }
        #expect(reason.contains("no thanks"))
        #expect(bad.isClosed, "a server that did not start is not left running")
        await host.stop()
    }

    @Test func `what the transport knows of a failure is added to the reason`() async throws {
        let bad = FakeMCPServer()
        bad.refuseInitialize()
        bad.diagnose("python: can't open file 'x.py'")
        let host = world.host([world.setting("bad")], ["bad": bad])
        host.start()
        await host.waitUntilSettled()
        guard case .failed(let reason) = host.status[0].state else {
            Issue.record("no failure")
            return
        }
        #expect(reason.contains("no thanks") && reason.contains("(python: can't open file 'x.py')"))
    }

    @Test func `a server that cannot be reached at all fails with the reason`() async throws {
        let host = world.host([world.setting("ghost")], [:])
        host.start()
        await host.waitUntilSettled()
        guard case .failed(let reason) = host.status[0].state else {
            Issue.record("no failure")
            return
        }
        #expect(reason.contains("no such fake"))
    }

    @Test func `a server that goes away takes its tools with it, and the person is told`() async throws {
        let fake = FakeMCPServer(tools: ["a"])
        let host = world.host([world.setting("srv")], ["srv": fake])
        var notices = host.notices.makeAsyncIterator()
        host.start()
        await host.waitUntilSettled()
        #expect(await notices.next() == "1 MCP server connected.", "first the startup summary")
        fake.end()
        let message = await notices.next()
        #expect(message?.contains("srv") == true && message?.contains("went away") == true)
        #expect(world.offered.isEmpty)
        guard case .failed = host.status[0].state else {
            Issue.record("still ready")
            return
        }
        #expect(try await world.call("mcp__srv__a").isError)
        await host.stop()
    }

    @Test func `a server that says its tools changed is asked again`() async throws {
        let fake = FakeMCPServer(tools: ["a"])
        let host = world.host([world.setting("srv")], ["srv": fake])
        host.start()
        await host.waitUntilSettled()
        fake.setTools(["a", "b"])
        fake.announceChange()
        await host.waitUntilListed("srv", times: 2)
        #expect(world.offered == ["mcp__srv__a", "mcp__srv__b"])
        await host.stop()
    }

    @Test func `stopping closes every server, and nothing is world.offered after`() async throws {
        let one = FakeMCPServer(tools: ["a"])
        let two = FakeMCPServer(tools: ["b"])
        let host = world.host([world.setting("one"), world.setting("two")], ["one": one, "two": two])
        host.start()
        await host.waitUntilSettled()
        await host.stop()
        #expect(one.isClosed && two.isClosed && world.offered.isEmpty)
        #expect(
            !host.status.contains { if case .failed = $0.state { true } else { false } }, "stopping is not a failure")
    }

    @Test func `stopping while a server is still starting closes it instead of waiting for it`() async throws {
        let slow = FakeMCPServer(tools: ["a"])
        slow.holdInitialize()
        let host = world.host([world.setting("slow")], ["slow": slow])
        host.start()
        await slow.waitForInitialize()
        await host.stop()
        #expect(slow.isClosed && world.offered.isEmpty)
    }
}
