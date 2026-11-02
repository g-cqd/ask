internal import AskAgentCore
internal import AskTUI
internal import AskTools

extension AgentConversation {
    /// The longest a turn waits for MCP servers; a server that takes longer joins later.
    static let mcpWait = Duration.seconds(10)

    /// The resources `server` lists, for the `@server:` picker (roadmap 0067); none for a name that is no configured server. Typing
    /// `@server:` is asking for them, so servers that wait for their first need are started, as a message would.
    func resourceRows(_ server: String) async -> [ChoiceRow] {
        guard mcp.status.contains(where: { $0.name == server && $0.state != .off }) else { return [] }
        await mcp.connect(waitingAtMost: Self.mcpWait)
        return (await mcp.listedResources(of: server) ?? [])
            .map {
                ChoiceRow(label: "@\(server):\($0.uri)", detail: $0.name, arguments: "@\(server):\($0.uri)")
            }
    }

    /// Before a turn: connects the MCP servers on their first need and waits for any still connecting, so the request offers their tools
    /// (roadmap 0143). The status bar says so meanwhile. A stopped turn stops waiting; the servers go on connecting.
    func connectMCP(update: @Sendable (ConversationUpdate) -> Void) async throws {
        guard mcp.isPending else { return }
        update(.connectingMCP(true))
        let settled = await mcp.connect(waitingAtMost: Self.mcpWait)
        update(.connectingMCP(false))
        if !settled, !Task.isCancelled {
            let names = mcp.pendingServers.joined(separator: ", ")
            update(.notice("Not waiting longer for \(names): the tools come once connected.", isError: false))
        }
        // As the loop says it, so a stop here is reported like any other: by colour, without a block (roadmap 0142).
        if Task.isCancelled { throw AgentError.cancelled }
    }
}
