internal import AskAI
public import AskAgentCore
public import AskMCP
internal import Foundation
internal import Synchronization

/// Connects the configured MCP servers in the background and offers their tools (ADR-0099).
///
/// Nothing waits for a server: starting one can take seconds (a package fetched and a process launched), and ask's start is budgeted in
/// milliseconds. Each server is its own task; one that fails costs only itself; what a server offers follows what it says, and goes
/// when it does. Non-interactive runs, which have no later turn to benefit, wait with ``waitUntilSettled()``.
public final class MCPHost: Sendable {
    /// How a server's transport is made, from its setting and its environment and headers once `${NAME}` is filled in.
    public typealias TransportFactory =
        @Sendable (MCPServerSetting, [String: String], [String: String]) throws -> any MCPTransport

    struct State {
        var statuses: [MCPServerStatus]
        var connections: [String: MCPConnection] = [:]
        var tasks: [Task<Void, Never>] = []
        var followers: [Task<Void, Never>] = []
        var stopping = false
        var listings: [String: Int] = [:]
        var waiters: [(server: String, times: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    /// The most tools a server may have to be offered whole without a `tools` list. A bigger one would put its schemas in every request.
    public static let defaultMaximumDirectTools = 16

    let servers: [MCPServerSetting]
    let live: LiveTools
    let environment: [String: String]
    let maximumDirectTools: Int
    let makeTransport: TransportFactory
    let state: Mutex<State>
    let noticeSink: AsyncStream<String>.Continuation
    let forward: (@Sendable (String) -> Void)?
    let catalog: MCPCatalog
    /// The group of the two search tools. A server's name cannot hold a `/`, so it cannot be this one.
    static let searchGroup = "mcp/search"

    /// What the host says as things happen: a server connected, skipped, failed or went away.
    public let notices: AsyncStream<String>

    /// A host for `servers`, offering their tools through `live`.
    /// - Parameters:
    ///   - servers: the configured servers.
    ///   - live: where the tools are offered.
    ///   - environment: what `${NAME}` is filled from.
    ///   - maximumDirectTools: the most tools a server with no `tools` list may have.
    ///   - transport: how a server's transport is made.
    ///   - forwarding: also told everything ``notices`` is, for a caller that outlives this host.
    public init(
        servers: [MCPServerSetting], live: LiveTools, environment: [String: String],
        maximumDirectTools: Int = MCPHost.defaultMaximumDirectTools, transport: @escaping TransportFactory,
        forwarding: (@Sendable (String) -> Void)? = nil
    ) {
        self.forward = forwarding
        self.servers = servers
        self.live = live
        catalog = MCPCatalog(live: live)
        self.environment = environment
        self.maximumDirectTools = maximumDirectTools
        self.makeTransport = transport
        state = Mutex(
            State(statuses: servers.map { MCPServerStatus(name: $0.name, state: $0.enabled ? .connecting : .off) }))
        (notices, noticeSink) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(64))
    }

    /// Where each server stands, in configuration order.
    public var status: [MCPServerStatus] { state.withLock { $0.statuses } }

    /// Begins connecting every enabled server, and returns at once.
    public func start() {
        let tasks = servers.filter(\.enabled).map { server in Task { await self.connect(server) } }
        state.withLock { $0.tasks = tasks }
    }

    /// Returns when every server has connected or failed.
    public func waitUntilSettled() async {
        let tasks = state.withLock { $0.tasks }
        for task in tasks { await task.value }
    }

    /// Returns once the tools of `server` have been listed `times` times: the first listing, and one for each change it announced.
    func waitUntilListed(_ server: String, times: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Bool in
                if state.listings[server, default: 0] >= times { return true }
                state.waiters.append((server, times, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// Closes every server; closing is what withdraws its tools.
    public func stop() async {
        let tasks = state.withLock { state -> [Task<Void, Never>] in
            state.stopping = true
            return state.tasks
        }
        for task in tasks { task.cancel() }
        for task in tasks { await task.value }
        let (connections, followers) = state.withLock { (Array($0.connections.values), $0.followers) }
        for connection in connections { await connection.close() }
        for follower in followers { await follower.value }
        noticeSink.finish()
    }
}
