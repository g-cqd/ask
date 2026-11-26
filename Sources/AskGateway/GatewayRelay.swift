/// The gateway's routing (ADR-0170, `docs/protocol/gateway.md`), with no network: frames come in on a connection, frames go out on
/// connections. Nodes and controllers each say who they are with `hello`; a controller's `open` names a node by its key, and the
/// gateway gives the channel a number of its own on that node's connection, then carries `data` and `close` both ways. It keeps each
/// node's sealed list for the controllers, and never reads a channel's content.
package struct GatewayRelay: Sendable {
    /// A connection, as the transport numbers them.
    package typealias Connection = Int

    /// What the transport does: send a frame on a connection, or end a connection that broke the protocol.
    package enum Outgoing: Sendable, Equatable {
        case send(Connection, RelayFrame)
        case drop(Connection, reason: String)
    }

    private enum Role {
        case node(key: [UInt8])
        case controller
    }

    private struct Route: Hashable {
        let controller: Connection
        let controllerChannel: UInt32
    }

    /// The most channels one controller may have open at once.
    package static let channelsPerController = 32

    private var roles: [Connection: Role] = [:]
    /// Each node's connection, by its static key (from the node's Noise handshake, never from what it says).
    private var nodes: [[UInt8]: Connection] = [:]
    private var lists: [[UInt8]: [UInt8]] = [:]
    /// A channel's two ends: the controller's number for it, and the node's.
    private var toNode: [Route: (node: Connection, channel: UInt32)] = [:]
    private var toController: [Connection: [UInt32: Route]] = [:]
    private var nextChannel: [Connection: UInt32] = [:]

    package init() {}

    /// A node connected; `key` is the static key its Noise handshake proved, checked against the enrolment by the transport.
    package mutating func nodeConnected(_ connection: Connection, key: [UInt8]) -> [Outgoing] {
        var out: [Outgoing] = []
        if let previous = nodes[key], previous != connection { out += disconnected(previous) }
        roles[connection] = .node(key: key)
        nodes[key] = connection
        return out
    }

    /// A controller connected, admitted by Cloudflare Access and the gateway's check of its assertion.
    package mutating func controllerConnected(_ connection: Connection) { roles[connection] = .controller }

    /// A connection ended: every channel through it is closed at its other end.
    package mutating func disconnected(_ connection: Connection) -> [Outgoing] {
        var out: [Outgoing] = []
        switch roles.removeValue(forKey: connection) {
            case .node(let key):
                if nodes[key] == connection {
                    nodes[key] = nil
                    lists[key] = nil
                }
                for (_, route) in toController.removeValue(forKey: connection) ?? [:] {
                    toNode[route] = nil
                    out.append(
                        Self.close(route.controller, route.controllerChannel, reason: 2, "the computer went away")
                    )
                }
            case .controller:
                for (route, end) in toNode where route.controller == connection {
                    toNode[route] = nil
                    toController[end.node]?[end.channel] = nil
                    out.append(Self.close(end.node, end.channel, reason: 0, "the controller went away"))
                }
            case nil: break
        }
        nextChannel[connection] = nil
        return out
    }

    /// What arrives on `connection`, and what it makes the gateway send.
    package mutating func receive(_ frame: RelayFrame, on connection: Connection) -> [Outgoing] {
        guard let role = roles[connection] else { return [] }
        switch (frame.kind, role) {
            case (.ping, _): return [.send(connection, Self.frame(.pong, 0, frame.body))]
            // A controller says hello for the lists, and gets every list again whenever a node sends a new one.
            case (.hello, .controller): return [.send(connection, listsFrame())]
            case (.hello, _), (.pong, _): return []
            case (.list, .node(let key)):
                lists[key] = frame.body
                let lists = listsFrame()
                return roles.compactMap { connection, role in
                    if case .controller = role { .send(connection, lists) } else { nil }
                }
            case (.lists, .controller): return []
            case (.open, .controller): return open(frame, from: connection)
            case (.data, .controller), (.close, .controller):
                let route = Route(controller: connection, controllerChannel: frame.channel)
                guard let end = toNode[route] else { return [] }
                if frame.kind == .close {
                    toNode[route] = nil
                    toController[end.node]?[end.channel] = nil
                }
                return [.send(end.node, Self.frame(frame.kind, end.channel, frame.body))]
            case (.data, .node), (.close, .node):
                guard let route = toController[connection]?[frame.channel] else { return [] }
                if frame.kind == .close {
                    toController[connection]?[frame.channel] = nil
                    toNode[route] = nil
                }
                return [.send(route.controller, Self.frame(frame.kind, route.controllerChannel, frame.body))]
            default:
                return [.drop(connection, reason: "a \(frame.kind) frame from the wrong side")]
        }
    }

    /// The lists of the nodes connected now, for a controller: each node's key, its list's length and the list.
    package func listsFrame() -> RelayFrame {
        var body: [UInt8] = []
        for (key, list) in lists.sorted(by: { $0.key.lexicographicallyPrecedes($1.key) }) where nodes[key] != nil {
            body += key + RelayBytes.u32(UInt32(list.count)) + list
        }
        return Self.frame(.lists, 0, body)
    }

    /// A controller's `open`: the node's key, then the controller's first message, which goes to the node on a channel numbered for
    /// it.
    private mutating func open(_ frame: RelayFrame, from controller: Connection) -> [Outgoing] {
        let route = Route(controller: controller, controllerChannel: frame.channel)
        guard frame.body.count >= 32 + 96, toNode[route] == nil else {
            return [Self.close(controller, frame.channel, reason: 4, "an opening the gateway cannot read")]
        }
        guard toNode.keys.filter({ $0.controller == controller }).count < Self.channelsPerController else {
            return [Self.close(controller, frame.channel, reason: 3, "too many channels open")]
        }
        let key = Array(frame.body.prefix(32))
        guard let node = nodes[key] else {
            return [Self.close(controller, frame.channel, reason: 2, "that computer is not connected")]
        }
        let channel = (nextChannel[node] ?? 0) &+ 1
        nextChannel[node] = channel
        toNode[route] = (node, channel)
        toController[node, default: [:]][channel] = route
        return [.send(node, Self.frame(.open, channel, Array(frame.body.dropFirst(32))))]
    }

    /// A frame the gateway builds: a parsed frame's body on another channel, or a body it wrote in its kind's shape.
    private static func frame(_ kind: RelayFrame.Kind, _ channel: UInt32, _ body: [UInt8]) -> RelayFrame {
        RelayFrame(checked: kind, channel: channel, body: body)
    }

    /// Closes channel `channel` (never 0) of `connection`, saying why.
    private static func close(_ connection: Connection, _ channel: UInt32, reason: UInt8, _ words: String) -> Outgoing {
        .send(connection, frame(.close, channel, [reason] + Array(words.utf8)))
    }
}
