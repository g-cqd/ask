internal import AskAgentCore
internal import AskTools
internal import Foundation

/// The MCP servers of `settings`, connecting (ADR-0099), and watched with the jobs so that ask being killed does not leave them (ADR-0102).
/// With none configured this does nothing.
func startMCPServers(_ settings: RunSettings, jobs: JobTable, connectsOnFirstNeed: Bool = false) -> MCPHub {
    let environment = LaunchEnvironment.values
    let hub = MCPHub(
        environment: environment, connectsOnFirstNeed: connectsOnFirstNeed,
        transport: MCPHub.standardTransport(inheriting: environment, jobs: jobs))
    hub.apply(settings.configuration.mcp.value.servers)
    return hub
}

/// One prompt and no later turn: wait for the servers, so the first request already has their tools, and say what did not start.
func waitForMCPServers(_ hub: MCPHub) async {
    await hub.waitUntilSettled()
    let lines = hub.status.compactMap { $0.problem ?? $0.remark }
    for line in lines { FileHandle.standardError.write(Data("ask: \(line)\n".utf8)) }
}
