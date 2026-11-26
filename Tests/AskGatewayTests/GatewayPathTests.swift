internal import CryptoKit
internal import Testing

@testable import AskGateway

/// The whole path in memory (ADR-0170): a controller, the gateway's routing and a node, every frame through its bytes as on the wire.
/// The controller reads the node's sealed list, opens a channel, attaches and receives the screen; an untrusted controller is
/// refused; either end going away closes the other; the gateway limits channels and drops a frame from the wrong side.
struct GatewayPathTests {
    private typealias Key = Curve25519.KeyAgreement.PrivateKey
    private let nodeKey = Key()
    private let controllerKey = Key()
    private let size = ChannelMessage.Size(columns: 100, rows: 30)!
    private static let (nodeConnection, controllerConnection) = (1, 2)

    /// A small world: the gateway's routing, one node, and what reached the controller.
    private struct World {
        var relay = GatewayRelay()
        var node: GatewayNode
        var toController: [RelayFrame] = []
        var events: [GatewayNode.Event] = []
        var dropped: [Int] = []

        /// Carries `outgoing` until nothing moves: to the node, or kept for the controller.
        mutating func deliver(_ outgoing: [GatewayRelay.Outgoing]) {
            var queue = outgoing
            while !queue.isEmpty {
                switch queue.removeFirst() {
                    case .send(GatewayPathTests.nodeConnection, let frame):
                        let (frames, events) = node.receive(Self.wire(frame))
                        self.events += events
                        for frame in frames {
                            queue += relay.receive(Self.wire(frame), on: GatewayPathTests.nodeConnection)
                        }
                    case .send(_, let frame): toController.append(Self.wire(frame))
                    case .drop(let connection, _): dropped.append(connection)
                }
            }
        }

        mutating func fromController(_ frame: RelayFrame) {
            deliver(relay.receive(Self.wire(frame), on: GatewayPathTests.controllerConnection))
        }

        mutating func fromNode(_ frames: [RelayFrame]) {
            for frame in frames { deliver(relay.receive(Self.wire(frame), on: GatewayPathTests.nodeConnection)) }
        }

        /// Through its bytes, as the wire carries it.
        static func wire(_ frame: RelayFrame) -> RelayFrame {
            // Every frame either side builds parses back: what the gateway relays must be well formed.
            (try? RelayFrame(parsing: frame.bytes)) ?? RelayFrame(checked: .close, channel: 9_999, body: [4])
        }
    }

    private func world(trusting trusted: [Key]) throws -> World {
        let keys = Set(trusted.map(\.publicKey.rawRepresentation))
        var world = World(node: GatewayNode(key: nodeKey) { keys.contains($0.rawRepresentation) })
        _ = world.relay.nodeConnected(Self.nodeConnection, key: Array(nodeKey.publicKey.rawRepresentation))
        world.relay.controllerConnected(Self.controllerConnection)
        world.fromNode([
            GatewayNode.hello, try GatewayNode.list(Array(#"{"sessions":["s1"]}"#.utf8), to: trusted.map(\.publicKey))
        ])
        return world
    }

    private func open(_ world: inout World, as key: Key, channel: UInt32 = 1) throws -> ControllerChannel {
        let (controller, first) = try ControllerChannel.open(controllerKey: key, nodeKey: nodeKey.publicKey)
        world.fromController(
            try RelayFrame(kind: .open, channel: channel, body: Array(nodeKey.publicKey.rawRepresentation) + first)
        )
        return controller
    }

    @Test func `a trusted controller reads the list, attaches, and receives the screen`() throws {
        var world = try world(trusting: [controllerKey])
        world.fromController(try RelayFrame(kind: .hello, body: [0, 1, 2]))
        let lists = try #require(world.toController.last { $0.kind == .lists })
        #expect(Array(lists.body.prefix(32)) == Array(nodeKey.publicKey.rawRepresentation))
        #expect(
            try SealedList.open(Array(lists.body.dropFirst(36)), with: controllerKey)
                == Array(#"{"sessions":["s1"]}"#.utf8)
        )

        var controller = try open(&world, as: controllerKey)
        let answer = try #require(world.toController.last { $0.kind == .data && $0.channel == 1 })
        try controller.finish(answer.body)
        world.fromController(
            try RelayFrame(kind: .data, channel: 1, body: try controller.send(.attach(size, session: "s1")))
        )
        #expect(
            world.events == [
                .attach(
                    channel: 1,
                    size: size,
                    session: "s1",
                    controller: GatewayKeys.fingerprint(controllerKey.publicKey)
                )
            ]
        )

        let screen = Array("\u{1B}[?1049h ask> ".utf8)
        world.toController.removeAll()
        world.fromNode(world.node.output(screen, on: 1))
        let output = try #require(world.toController.first)
        #expect(try controller.receive(output.body) == .output(screen))
    }

    @Test func `an untrusted controller is refused, and learns nothing`() throws {
        var world = try world(trusting: [controllerKey])
        _ = try open(&world, as: Key())
        let close = try #require(world.toController.last)
        #expect(close.kind == .close && close.body.first == 1)
        #expect(world.node.openChannels.isEmpty && world.events.isEmpty)
    }

    @Test func `the node going away closes the controller's channel, and the controller going away closes the node's`()
        throws
    {
        var world = try world(trusting: [controllerKey])
        var controller = try open(&world, as: controllerKey)
        try controller.finish(try #require(world.toController.last).body)
        world.deliver(world.relay.disconnected(Self.nodeConnection))
        #expect(world.toController.last?.kind == .close && world.toController.last?.body.first == 2)

        var again = try self.world(trusting: [controllerKey])
        _ = try open(&again, as: controllerKey)
        #expect(again.node.openChannels == [1])
        again.deliver(again.relay.disconnected(Self.controllerConnection))
        #expect(again.node.openChannels.isEmpty && again.events.last == .closed(channel: 1))
    }

    @Test func `the gateway limits a controller's channels, and drops a frame from the wrong side`() throws {
        var world = try world(trusting: [controllerKey])
        for channel in 1 ... UInt32(GatewayRelay.channelsPerController + 1) {
            _ = try open(&world, as: controllerKey, channel: channel)
        }
        #expect(world.toController.last?.kind == .close && world.toController.last?.body.first == 3)
        world.deliver(world.relay.receive(try RelayFrame(kind: .lists, body: []), on: Self.nodeConnection))
        #expect(world.dropped == [Self.nodeConnection])
    }

    @Test func `a channel to a computer that is not connected is closed at once`() throws {
        var world = try world(trusting: [controllerKey])
        let (_, first) = try ControllerChannel.open(controllerKey: controllerKey, nodeKey: Key().publicKey)
        world.fromController(
            try RelayFrame(kind: .open, channel: 5, body: Array(Key().publicKey.rawRepresentation) + first)
        )
        #expect(world.toController.last?.kind == .close && world.toController.last?.body.first == 2)
    }
}
