import AskAI
import AskAgentCore
import AskMCP
import Foundation

@testable import AskTools

/// What the host's suites share: a registry of live tools, a host over played servers, and calls through the registry.
struct MCPWorld {
    let live = LiveTools()
    let context = ToolContext(workingDirectory: "/tmp")

    /// A host for `servers`, whose transports are `fakes` by name.
    func host(
        _ servers: [MCPServerSetting], _ fakes: [String: FakeMCPServer], environment: [String: String] = [:],
        maximumDirectTools: Int = 16
    ) -> MCPHost {
        MCPHost(
            servers: servers, live: live, environment: environment, maximumDirectTools: maximumDirectTools,
            transport: { server, _, _ in
                guard let fake = fakes[server.name] else { throw MCPError.refusedEndpoint("no such fake") }
                return fake
            })
    }

    /// A command server called `name`.
    func setting(_ name: String, tools: [String]? = nil, enabled: Bool = true) -> MCPServerSetting {
        MCPServerSetting(name: name, command: "x", tools: tools, enabled: enabled)
    }

    /// The names of the tools offered now.
    var offered: [String] { (try? ToolRegistry([], live: live))?.definitions.map(\.name) ?? [] }

    /// Calls `name` through the registry.
    func call(_ name: String, _ json: String = "{}") async throws -> ToolOutput {
        try await ToolRegistry([], live: live)
            .run(
                name: name, input: try JSONObject(validating: Array(json.utf8)), in: context)
    }
}
