internal import CryptoKit
internal import Testing

@testable import AskGateway

/// One end-to-end channel, controller to node, through a relay that only carries bytes (ADR-0170): a trusted controller attaches
/// and receives output, split and joined again when large; an untrusted one is refused; a node with another key cannot answer, and
/// the relay changing a byte ends nothing but that message.
struct ChannelTests {
    private typealias Key = Curve25519.KeyAgreement.PrivateKey
    private let node = Key()
    private let controller = Key()
    private let size = ChannelMessage.Size(columns: 120, rows: 40)!

    private func opened() throws -> (ControllerChannel, NodeChannel) {
        var (controllerSide, first) = try ControllerChannel.open(controllerKey: controller, nodeKey: node.publicKey)
        let trusted = controller.publicKey.rawRepresentation
        let (nodeSide, answer) = try NodeChannel.accept(first, nodeKey: node) { $0.rawRepresentation == trusted }
        try controllerSide.finish(answer)
        return (controllerSide, nodeSide)
    }

    @Test func `a trusted controller attaches, and the node's output reaches it in order`() throws {
        var (controllerSide, nodeSide) = try opened()
        #expect(controllerSide.isOpen)
        #expect(
            try nodeSide.receive(try controllerSide.send(.attach(size, session: "s1"))) == .attach(size, session: "s1")
        )
        let screen = Array("\u{1B}[?1049h\u{1B}[2J ask> ".utf8)
        let sealed = try nodeSide.send(.output(screen))
        #expect(sealed.count == 1)
        #expect(try controllerSide.receive(sealed[0]) == .output(screen))
        #expect(nodeSide.controller.rawRepresentation == controller.publicKey.rawRepresentation)
    }

    @Test func `output larger than one message is split, and joins back whole`() throws {
        var (controllerSide, nodeSide) = try opened()
        let large = (0 ..< 200_000).map { UInt8(truncatingIfNeeded: $0) }
        let sealed = try nodeSide.send(.output(large))
        #expect(sealed.count == 4)
        var joined: [UInt8] = []
        for message in sealed {
            guard case .output(let bytes) = try controllerSide.receive(message) else {
                Issue.record("not output")
                return
            }
            joined += bytes
        }
        #expect(joined == large)
        // Nested inside the node's link: each piece fits a relay frame, and each frame one Noise message of the link.
        for message in sealed {
            let frame = try RelayFrame(kind: .data, channel: 1, body: message)
            #expect(frame.bytes.count <= 65_535 - 16)
        }
    }

    @Test func `an untrusted controller is refused before the node answers`() throws {
        let (_, first) = try ControllerChannel.open(controllerKey: Key(), nodeKey: node.publicKey)
        #expect(throws: NodeChannel.Failure.untrusted) {
            _ = try NodeChannel.accept(first, nodeKey: node) {
                $0.rawRepresentation == controller.publicKey.rawRepresentation
            }
        }
    }

    @Test func `a node holding another key cannot read the opening`() throws {
        let (_, first) = try ControllerChannel.open(controllerKey: controller, nodeKey: node.publicKey)
        #expect(throws: NodeChannel.Failure.handshake(.cipher(.authenticationFailed))) {
            _ = try NodeChannel.accept(first, nodeKey: Key()) { _ in true }
        }
    }

    @Test func `a byte changed by the relay is refused, and the channel goes on`() throws {
        var (controllerSide, nodeSide) = try opened()
        let sealed = try controllerSide.send(.input(Array("y".utf8)))
        var changed = sealed
        changed[changed.count - 1] ^= 0x80
        #expect(throws: NodeChannel.Failure.handshake(.cipher(.authenticationFailed))) { try nodeSide.receive(changed) }
        #expect(try nodeSide.receive(sealed) == .input(Array("y".utf8)))
    }
}
