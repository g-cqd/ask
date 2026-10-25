internal import AskAgentCore
internal import AskTools
internal import Foundation

/// The MCP servers of `settings`, connecting (ADR-0099). With none configured this does nothing.
func startMCPServers(_ settings: RunSettings) -> MCPHub {
    let environment = ProcessInfo.processInfo.environment
    let hub = MCPHub(environment: environment, transport: MCPHub.standardTransport(inheriting: environment))
    hub.apply(settings.configuration.mcp.value.servers)
    return hub
}

/// One prompt and no later turn: wait for the servers, so the first request already has their tools, and say what did not start.
func waitForMCPServers(_ hub: MCPHub) async {
    await hub.waitUntilSettled()
    for line in hub.status.compactMap(\.problem) { FileHandle.standardError.write(Data("ask: \(line)\n".utf8)) }
}
