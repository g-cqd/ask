internal import AskAI
internal import AskAgentCore
internal import AskMCP
internal import Foundation
internal import Synchronization

extension MCPHost {
    /// Starts one server, lists its tools, offers them, and then follows it until it goes.
    func connect(_ server: MCPServerSetting) async {
        let transport: any MCPTransport
        do {
            transport = try makeTransport(
                server, try MCPExpansion.expand(server.env, from: environment),
                try MCPExpansion.expand(server.headers, from: environment))
        } catch let missing as MCPExpansion.Missing {
            return fail(server, "the setting names ${\(missing.name)}, which is not set in ask's environment")
        } catch {
            return fail(server, MCPFailure.describe(error, server: server.name))
        }
        let connection = MCPConnection(transport: transport, clientName: "ask", clientVersion: "0")
        // Known before it starts, so that stopping the host reaches a server that is still starting.
        let registered = state.withLock { state -> Bool in
            guard !state.stopping else { return false }
            state.connections[server.name] = connection
            return true
        }
        guard registered else { return await connection.close() }
        do {
            _ = try await connection.start()
            try await offer(server, connection)
        } catch {
            await connection.close()
            let more = transport.diagnostic.map { " (\($0))" } ?? ""
            return fail(server, MCPFailure.describe(error, server: server.name) + more)
        }
        let follower = Task { await self.follow(server, connection) }
        state.withLock { $0.followers.append(follower) }
    }

    /// Follows a connected server until it is gone: its tool list when it says it changed, and its end.
    private func follow(_ server: MCPServerSetting, _ connection: MCPConnection) async {
        for await event in connection.events {
            switch event {
                case .toolsChanged: try? await offer(server, connection, announce: false)
                case .closed: gone(server)
                case .log, .malformed: continue
            }
        }
    }

    /// Lists the server's tools and offers the ones that are wanted: whole, or, when there are too many to list, through the search.
    private func offer(_ server: MCPServerSetting, _ connection: MCPConnection, announce: Bool = true)
        async throws(MCPError)
    {
        let tools = try await connection.listTools()
        let (chosen, notes) = Self.select(from: tools, for: server)
        let searched =
            server.mode == .search
            || (server.mode == nil && server.tools == nil
                && tools.count > Swift.max(0, server.maxDirectTools ?? maximumDirectTools))
        if searched {
            live.replace(group: server.name, with: [])
            catalog.set(server: server.name, tools: chosen, connection: connection)
            setStatus(server.name, .searchable(tools: chosen.count), notes: notes)
            if announce, let remark = status.first(where: { $0.name == server.name })?.remark { say(remark) }
        } else {
            catalog.remove(server: server.name)
            live.replace(group: server.name, with: Self.adapters(chosen, server: server.name, connection: connection))
            setStatus(server.name, .ready(offered: chosen.count, of: tools.count), notes: notes)
            if announce { say("MCP server \(server.name) connected: \(chosen.count) of \(tools.count) tools offered.") }
        }
        publishSearch()
        countListing(server.name)
    }

    /// Offers the two search tools while any server is searched, and withdraws them when none is.
    private func publishSearch() {
        let tools: [any Tool] =
            catalog.servers.isEmpty ? [] : [MCPSearchTool(catalog: catalog), MCPCallTool(catalog: catalog)]
        live.replace(group: Self.searchGroup, with: tools)
    }

    /// The tools `server` asked for, and a note for each it asked for that the server does not have.
    private static func select(from tools: [MCPTool], for server: MCPServerSetting) -> ([MCPTool], [String]) {
        guard let wanted = server.tools else { return (tools, []) }
        let have = Set(tools.map(\.name))
        let missing = wanted.filter { !have.contains($0) }
        return (
            tools.filter { wanted.contains($0.name) },
            missing.isEmpty ? [] : ["listed in tools but not offered by the server: \(missing.joined(separator: ", "))"]
        )
    }

    private static func adapters(_ tools: [MCPTool], server: String, connection: MCPConnection) -> [any Tool] {
        tools.map { tool in
            MCPToolAdapter(
                server: server, tool: tool, name: MCPToolName.make(server: server, tool: tool.name),
                connection: connection)
        }
    }

    private func gone(_ server: MCPServerSetting) {
        let stopping = state.withLock { $0.stopping }
        live.replace(group: server.name, with: [])
        catalog.remove(server: server.name)
        publishSearch()
        guard !stopping else { return }
        setStatus(server.name, .failed("the server went away"), notes: [])
        say("The MCP server \(server.name) went away; its tools are gone.")
    }

    private func fail(_ server: MCPServerSetting, _ reason: String) {
        setStatus(server.name, .failed(reason), notes: [])
        say("MCP server \(server.name) did not start: \(reason)")
    }

    private func setStatus(_ name: String, _ next: MCPServerStatus.State, notes: [String]) {
        state.withLock { state in
            guard let index = state.statuses.firstIndex(where: { $0.name == name }) else { return }
            state.statuses[index].state = next
            state.statuses[index].notes = notes
        }
    }

    private func countListing(_ server: String) {
        let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.listings[server, default: 0] += 1
            var ready: [CheckedContinuation<Void, Never>] = []
            state.waiters.removeAll { waiter in
                guard waiter.server == server, state.listings[server, default: 0] >= waiter.times else { return false }
                ready.append(waiter.continuation)
                return true
            }
            return ready
        }
        for continuation in ready { continuation.resume() }
    }
}

extension MCPHost {
    /// Tells whoever is listening.
    func say(_ line: String) {
        noticeSink.yield(line)
        forward?(line)
    }
}
