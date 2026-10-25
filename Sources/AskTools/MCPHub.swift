public import AskAgentCore
internal import AskMCP
internal import Foundation
internal import Synchronization

/// Keeps the MCP servers across loop rebuilds and follows the configuration (ADR-0099).
///
/// The agent loop is rebuilt whenever the configuration changes, and a server is a process that took seconds to start: the hub
/// outlives the loop, and `apply` starts or stops only what changed. The loop reads the tools through ``live``.
public final class MCPHub: Sendable {
    private struct State {
        var servers: [MCPServerSetting] = []
        var host: MCPHost?
        var chain: Task<Void, Never>?
    }

    /// The tools the servers offer now. Give it to the tool registry.
    public let live = LiveTools()
    /// What the hosts say, in one stream across changes: a server connected, failed or went away.
    public let notices: AsyncStream<String>
    private let noticeSink: AsyncStream<String>.Continuation
    private let environment: [String: String]
    private let transport: MCPHost.TransportFactory
    private let state = Mutex(State())

    /// A hub whose servers are made by `transport`.
    /// - Parameters:
    ///   - environment: what `${NAME}` in a server's settings is filled from.
    ///   - transport: how a server's transport is made; ``standardTransport(userAgent:)`` for real ones.
    public init(environment: [String: String], transport: @escaping MCPHost.TransportFactory) {
        self.environment = environment
        self.transport = transport
        (notices, noticeSink) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(64))
    }

    /// Where each server stands.
    public var status: [MCPServerStatus] { state.withLock { $0.host?.status ?? [] } }

    /// Makes `servers` the ones that run. Returns at once; nothing happens if they are the ones already running.
    public func apply(_ servers: [MCPServerSetting]) {
        state.withLock { state in
            guard servers != state.servers else { return }
            state.servers = servers
            let old = state.host
            let before = state.chain
            let sink = noticeSink
            let next =
                servers.isEmpty
                ? nil
                : MCPHost(
                    servers: servers, live: live, environment: environment, transport: transport,
                    forwarding: { sink.yield($0) })
            state.host = next
            // One at a time: the old servers are gone before the new start, so a server whose setting changed is never running twice.
            state.chain = Task {
                await before?.value
                await old?.stop()
                next?.start()
            }
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
