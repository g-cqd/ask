internal import CryptoKit
internal import Synchronization
internal import Testing

@testable import AskGateway

/// A node and the gateway over a real TCP connection on the loopback address: the listener binds the address it is given, the link's
/// handshake checks both keys, and frames cross both ways, a large one too.
struct TCPLinkTests {
    private typealias Key = Curve25519.KeyAgreement.PrivateKey

    @Test(.timeLimit(.minutes(1)))
    func `a node reaches the gateway over TCP, and frames cross both ways`() async throws {
        let (node, gateway) = (Key(), Key())
        let (accepted, arrive) = AsyncStream<TCPStream>.makeStream()
        let listener = try TCPListener(host: "127.0.0.1", port: 0) { arrive.yield($0) }
        let port = listener.port
        defer { listener.stop() }
        #expect(port > 0)

        async let nodeSide = NoiseLink.node(
            over: try await TCPStream.connect(host: "127.0.0.1", port: Int(port)),
            key: node,
            gatewayKey: gateway.publicKey
        )
        var iterator = accepted.makeAsyncIterator()
        let incoming = try #require(await iterator.next())
        let gatewayLink = try await NoiseLink.gateway(over: incoming, key: gateway) {
            $0.rawRepresentation == node.publicKey.rawRepresentation
        }
        let nodeLink = try await nodeSide

        try await nodeLink.send(GatewayNode.hello)
        #expect(try await gatewayLink.receive() == GatewayNode.hello)
        let large = try RelayFrame(
            kind: .data,
            channel: 7,
            body: [UInt8](repeating: 0x5A, count: RelayFrame.maximumBody)
        )
        try await gatewayLink.send(large)
        #expect(try await nodeLink.receive() == large)
        await nodeLink.close()
        #expect(try await gatewayLink.receive() == nil)
    }
}
