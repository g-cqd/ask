import AskAI
import AskAgentCore
import AskMCP
import Foundation
import Testing

@testable import AskTools

/// What a call to a server's tool does (ADR-0099): arguments reach it, variables are filled in before it starts, a narrowed session is refused,
/// and a failure is an error output.
@Suite("A server's tools are called with the model's arguments, under ask's rules", .timeLimit(.minutes(1)))
struct MCPHostCallTests {
    private let world = MCPWorld()

    @Test func `a tool call goes to the server with the model's arguments and comes back as text`() async throws {
        let fake = FakeMCPServer(tools: ["search"])
        let host = world.host([world.setting("srv")], ["srv": fake])
        host.start()
        await host.waitUntilSettled()
        let output = try await world.call("mcp__srv__search", #"{"q":"urlsession"}"#)
        #expect(output == ToolOutput("ran search"))
        #expect(fake.calls.map(\.name) == ["search"] && fake.calls.first?.arguments == #"{"q":"urlsession"}"#)
        await host.stop()
    }

    @Test func `variables in a server's settings are filled from ask's environment before the server is started`()
        async throws
    {
        let seen = Seen()
        let host = MCPHost(
            servers: [
                MCPServerSetting(
                    name: "srv", url: "https://h.test/mcp", headers: ["Authorization": "Bearer ${TOKEN}"])
            ], live: world.live, environment: ["TOKEN": "abc"], maximumDirectTools: 16,
            transport: { _, environment, headers in
                seen.set(environment, headers)
                return FakeMCPServer(tools: ["a"])
            })
        host.start()
        await host.waitUntilSettled()
        #expect(seen.headers == ["Authorization": "Bearer abc"])
        await host.stop()
    }

    @Test func `a variable that is not set fails that server and starts nothing`() async throws {
        let seen = Seen()
        let host = MCPHost(
            servers: [MCPServerSetting(name: "srv", command: "x", env: ["K": "${MISSING}"])], live: world.live,
            environment: [:],
            maximumDirectTools: 16,
            transport: { _, environment, headers in
                seen.set(environment, headers)
                return FakeMCPServer()
            })
        host.start()
        await host.waitUntilSettled()
        guard case .failed(let reason) = host.status[0].state else {
            Issue.record("no failure")
            return
        }
        #expect(reason.contains("MISSING") && !seen.wasCalled)
    }

    @Test func `a tool of a narrowed session is refused, because a server is outside the sandbox`() async throws {
        let fake = FakeMCPServer(tools: ["a"])
        let host = world.host([world.setting("srv")], ["srv": fake])
        host.start()
        await host.waitUntilSettled()
        let narrowing = SessionNarrowing()
        narrowing.policy = SandboxPolicy(network: .none)
        let narrowed = ToolContext(workingDirectory: "/tmp", sandbox: .unrestricted, narrowing: narrowing)
        let output = try await ToolRegistry([], live: world.live)
            .run(
                name: "mcp__srv__a", input: try JSONObject(validating: Array("{}".utf8)), in: narrowed)
        #expect(output.isError && output.content.contains("sandbox") && fake.calls.isEmpty)
        await host.stop()
    }

    @Test func `a server's own error is an error output, and a tool that failed is one too`() async throws {
        let fake = FakeMCPServer(tools: ["a"])
        fake.reply { _, _ in #"{"content":[{"type":"text","text":"bad input"}],"isError":true}"# }
        let host = world.host([world.setting("srv")], ["srv": fake])
        host.start()
        await host.waitUntilSettled()
        #expect(try await world.call("mcp__srv__a") == ToolOutput.error("bad input"))
        await host.stop()
    }
}
