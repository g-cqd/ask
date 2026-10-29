public import AskAgentCore
internal import AskMCP
internal import Foundation
internal import Synchronization

/// Keeps the MCP servers across loop rebuilds and follows the configuration (ADR-0099).
///
/// The agent loop is rebuilt whenever the configuration changes, and a server is a process that took seconds to start: the hub
/// outlives the loop, and `apply` starts or stops only what changed. The loop reads the tools through ``live``.
public final class MCPHub: Sendable {
    struct State {
        var servers: [MCPServerSetting] = []
        var host: MCPHost?
        var chain: Task<Void, Never>?
        /// Whether servers start as they are applied: false until the first need, for a hub that waits for it (roadmap 0143).
        var started = true
    }

    /// The tools the servers offer now. Give it to the tool registry.
    public let live = LiveTools()
    /// What the hosts say, in one stream across changes: a server connected, failed or went away.
    public let notices: AsyncStream<String>
    private let noticeSink: AsyncStream<String>.Continuation
    private let environment: [String: String]
    private let transport: MCPHost.TransportFactory
    let state = Mutex(State())

    /// A hub whose servers are made by `transport`.
    /// - Parameters:
    ///   - environment: what `${NAME}` in a server's settings is filled from.
    ///   - connectsOnFirstNeed: start nothing until ``connect()`` (roadmap 0143), so an idle ask holds no server: an interactive
    ///     session's hub. A one-shot run's connects at once.
    ///   - transport: how a server's transport is made; ``standardTransport(userAgent:)`` for real ones.
    public init(
        environment: [String: String], connectsOnFirstNeed: Bool = false, transport: @escaping MCPHost.TransportFactory
    ) {
        self.environment = environment
        self.transport = transport
        (notices, noticeSink) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(64))
        state.withLock { $0.started = !connectsOnFirstNeed }
    }

    /// Where each server stands; before the first need, each enabled one is waiting.
    public var status: [MCPServerStatus] {
        state.withLock { state in
            guard state.started else {
                return state.servers.map { MCPServerStatus(name: $0.name, state: $0.enabled ? .waiting : .off) }
            }
            return state.host?.status ?? []
        }
    }

    /// Makes `servers` the ones that run. Returns at once; nothing happens if they are the ones already running. Before the first need,
    /// they are only kept.
    public func apply(_ servers: [MCPServerSetting]) {
        state.withLock { state in
            guard servers != state.servers else { return }
            state.servers = servers
            if state.started { launch(&state) }
        }
    }

    /// Replaces the running host with one for `state.servers`. One at a time: the old servers are gone before the new start, so a server
    /// whose setting changed is never running twice.
    func launch(_ state: inout State) {
        let old = state.host
        let before = state.chain
        let sink = noticeSink
        let next =
            state.servers.isEmpty
            ? nil
            : MCPHost(
                servers: state.servers, live: live, environment: environment, transport: transport,
                forwarding: { sink.yield($0) })
        state.host = next
        state.chain = Task {
            await before?.value
            await old?.stop()
            next?.start()
        }
    }

    /// What `/mcp` shows for `statuses`: a line each, with notes under, or how to add a server.
    public static func report(_ statuses: [MCPServerStatus]) -> [String] { MCPReport.lines(statuses) }

    /// Returns when every server that is starting has connected or failed.
    public func waitUntilSettled() async {
        let (chain, host) = state.withLock { ($0.chain, $0.host) }
        await chain?.value
        await host?.waitUntilSettled()
    }

    /// Stops every server and ends the notices.
    public func stop() async {
        let (chain, host) = state.withLock { state -> (Task<Void, Never>?, MCPHost?) in
            defer { state.host = nil }
            return (state.chain, state.host)
        }
        await chain?.value
        await host?.stop()
        noticeSink.finish()
    }
}
