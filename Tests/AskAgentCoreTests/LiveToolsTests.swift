import AskAI
import Testing

@testable import AskAgentCore

/// Tools that come and go while a session runs (ADR-0099): a server's tools arrive when it has connected, and leave when it goes.
@Suite("A registry offers the tools that are there now, and treats a foreign tool's arguments as its own")
struct LiveToolsTests {
    private struct Named: Tool {
        let definition: ToolDefinition
        let reply: String
        init(_ name: String, reply: String = "ok") {
            definition = ToolDefinition(
                name: name, description: name,
                inputSchema: try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8)))
            self.reply = reply
        }
        func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
            ToolOutput(reply == "echo" ? String(decoding: input.bytes, as: UTF8.self) : reply)
        }
    }

    private let context = ToolContext(workingDirectory: "/tmp")
    private func input(_ json: String) -> JSONObject { try! JSONObject(validating: Array(json.utf8)) }

    @Test func `a tool that arrives is offered and runs, and one that leaves is gone`() async throws {
        let live = LiveTools()
        let registry = try ToolRegistry([Named("built-in")], live: live)
        #expect(registry.definitions.map(\.name) == ["built-in"])
        live.replace(group: "rea", with: [Named("mcp__rea__a", reply: "from a")])
        #expect(registry.definitions.map(\.name) == ["built-in", "mcp__rea__a"])
        #expect(await registry.run(name: "mcp__rea__a", input: input("{}"), in: context) == ToolOutput("from a"))
        live.replace(group: "rea", with: [])
        #expect(registry.definitions.map(\.name) == ["built-in"])
        #expect(await registry.run(name: "mcp__rea__a", input: input("{}"), in: context).isError)
    }

    @Test func `groups keep the order they first arrived in, and replacing one keeps its place`() throws {
        let live = LiveTools()
        let registry = try ToolRegistry([], live: live)
        live.replace(group: "b", with: [Named("b1")])
        live.replace(group: "a", with: [Named("a1")])
        live.replace(group: "b", with: [Named("b1"), Named("b2")])
        #expect(registry.definitions.map(\.name) == ["b1", "b2", "a1"])
    }

    @Test func `a live tool cannot take the name of a built-in, and the built-in keeps it`() async throws {
        let live = LiveTools()
        let registry = try ToolRegistry([Named("bash", reply: "built-in")], live: live)
        live.replace(group: "x", with: [Named("bash", reply: "impostor")])
        #expect(registry.definitions.map(\.name) == ["bash"])
        #expect(await registry.run(name: "bash", input: input("{}"), in: context) == ToolOutput("built-in"))
    }

    @Test func `two groups cannot offer one name: the earlier keeps it`() async throws {
        let live = LiveTools()
        let registry = try ToolRegistry([], live: live)
        live.replace(group: "a", with: [Named("same", reply: "a")])
        live.replace(group: "b", with: [Named("same", reply: "b")])
        #expect(registry.definitions.map(\.name) == ["same"])
        #expect(await registry.run(name: "same", input: input("{}"), in: context) == ToolOutput("a"))
    }

    @Test func `a live tool's output is capped like any other`() async throws {
        let live = LiveTools()
        let registry = try ToolRegistry([], cap: OutputCap(maximumLines: 3, maximumBytes: 10_000), live: live)
        live.replace(group: "g", with: [Named("long", reply: (1 ... 50).map { "line \($0)" }.joined(separator: "\n"))])
        let output = await registry.run(name: "long", input: input("{}"), in: context)
        #expect(output.content.contains("omitted") && !output.content.contains("line 25"))
    }

    @Test func `a foreign tool's own sandbox argument is its argument, not a request to narrow ask's sandbox`()
        async throws
    {
        let live = LiveTools()
        let registry = try ToolRegistry([], live: live)
        live.replace(group: "g", with: [Named("t", reply: "echo")])
        let output = await registry.run(name: "t", input: input(#"{"sandbox":"Xcode"}"#), in: context)
        #expect(output == ToolOutput(#"{"sandbox":"Xcode"}"#))
    }

    @Test func `a foreign tool runs under the policy the session narrowed to, which it can see`() async throws {
        struct Spy: Tool {
            let definition = ToolDefinition(
                name: "spy", description: "",
                inputSchema: try! JSONObject(validating: Array(#"{"type":"object"}"#.utf8)))
            func run(_ input: JSONObject, in context: ToolContext) async -> ToolOutput {
                ToolOutput(context.sandbox == context.runSandbox ? "whole" : "narrowed")
            }
        }
        let live = LiveTools()
        let registry = try ToolRegistry([], live: live)
        live.replace(group: "g", with: [Spy()])
        let narrowing = SessionNarrowing()
        narrowing.policy = SandboxPolicy(network: .none)
        let narrowed = ToolContext(workingDirectory: "/tmp", sandbox: .unrestricted, narrowing: narrowing)
        #expect(await registry.run(name: "spy", input: input("{}"), in: narrowed).content == "narrowed")
        #expect(await registry.run(name: "spy", input: input("{}"), in: context).content == "whole")
    }

    @Test func `many tasks replacing and reading at once see whole snapshots`() async throws {
        let live = LiveTools()
        let registry = try ToolRegistry([], live: live)
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 50 {
                group.addTask { live.replace(group: "g\(index % 5)", with: [Named("t\(index)")]) }
                group.addTask { _ = registry.definitions }
            }
        }
        #expect(registry.definitions.count == 5)
    }
}
