internal import CryptoKit
internal import Synchronization
internal import Testing

@testable import AskGateway

/// A node and the gateway over a byte stream (ADR-0170): with the right keys, frames go both ways; a node refuses an impostor gateway
/// before its own key is sent; the gateway refuses a node it has not enrolled.
struct NoiseLinkTests {
    private typealias Key = Curve25519.KeyAgreement.PrivateKey

    @Test func `with the right keys, frames go both ways`() async throws {
        let (nodeEnd, gatewayEnd) = MemoryStream.pair()
        let (node, gateway) = (Key(), Key())
        async let gatewaySide = NoiseLink.gateway(over: gatewayEnd, key: gateway) {
            $0.rawRepresentation == node.publicKey.rawRepresentation
        }
        let nodeLink = try await NoiseLink.node(over: nodeEnd, key: node, gatewayKey: gateway.publicKey)
        let gatewayLink = try await gatewaySide
        #expect(gatewayLink.remoteKey.rawRepresentation == node.publicKey.rawRepresentation)
        try await nodeLink.send(GatewayNode.hello)
        #expect(try await gatewayLink.receive() == GatewayNode.hello)
        let ping = try RelayFrame(kind: .ping, body: [1, 2, 3, 4, 5, 6, 7, 8])
        try await gatewayLink.send(ping)
        #expect(try await nodeLink.receive() == ping)
        await nodeLink.close()
        #expect(try await gatewayLink.receive() == nil)
    }

    @Test func `frames sent at once all open: they reach the wire in the order they were sealed`() async throws {
        let (nodeEnd, gatewayEnd) = MemoryStream.pair()
        let (node, gateway) = (Key(), Key())
        async let gatewaySide = NoiseLink.gateway(over: gatewayEnd, key: gateway) { _ in true }
        let nodeLink = try await NoiseLink.node(over: nodeEnd, key: node, gatewayKey: gateway.publicKey)
        let gatewayLink = try await gatewaySide
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 1 ... 200 {
                group.addTask {
                    try await nodeLink.send(try RelayFrame(kind: .data, channel: UInt32(index), body: [1]))
                }
            }
            try await group.waitForAll()
        }
        var channels: Set<UInt32> = []
        for _ in 1 ... 200 { channels.insert(try #require(try await gatewayLink.receive()).channel) }
        #expect(channels == Set(1 ... 200))
    }

    @Test func `a node refuses an impostor gateway before sending its own key`() async throws {
        let (nodeEnd, impostorEnd) = MemoryStream.pair()
        let node = Key()
        async let impostor = NoiseLink.gateway(over: impostorEnd, key: Key()) { _ in true }
        await #expect(throws: NoiseLink.Failure.wrongKey) {
            _ = try await NoiseLink.node(over: nodeEnd, key: node, gatewayKey: Key().publicKey)
        }
        _ = try? await impostor
        // Only the first handshake message left the node: its ephemeral key, never its static one.
        let sent: [[UInt8]] = nodeEnd.sent.withLock { $0 }
        let firstLength: Int = sent.first?.count ?? 0
        #expect(sent.count == 1)
        #expect(firstLength == 2 + 32)
    }

    @Test func `the gateway refuses a node it has not enrolled`() async throws {
        let (nodeEnd, gatewayEnd) = MemoryStream.pair()
        let gateway = Key()
        async let nodeSide = NoiseLink.node(over: nodeEnd, key: Key(), gatewayKey: gateway.publicKey)
        await #expect(throws: NoiseLink.Failure.wrongKey) {
            _ = try await NoiseLink.gateway(over: gatewayEnd, key: gateway) { _ in false }
        }
        _ = try? await nodeSide
    }
}
