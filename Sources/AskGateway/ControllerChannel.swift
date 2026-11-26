package import CryptoKit

/// A controller's side of one end-to-end channel (ADR-0170): it opens with the node's static key, which it knows from the
/// dashboard's signed list, so only that node can answer; then it seals what the person does and opens what the node sends.
package struct ControllerChannel: Sendable {
    private var handshake: NoiseHandshake?
    private var transport: NoiseTransport?

    /// The first message, for the `open` frame.
    /// - Parameters:
    ///   - controllerKey: the person's controller key.
    ///   - nodeKey: the node's static key; a node holding another cannot read the message.
    /// - Returns: the channel, waiting for the node's answer, and the message to send.
    /// - Throws: a handshake failure, which a well-formed key never causes.
    package static func open(
        controllerKey: Curve25519.KeyAgreement.PrivateKey,
        nodeKey: Curve25519.KeyAgreement.PublicKey
    ) throws(NoiseHandshake.Failure) -> (channel: ControllerChannel, first: [UInt8]) {
        var handshake = try NoiseHandshake(
            pattern: .ik,
            initiator: true,
            localStatic: controllerKey,
            remoteStatic: nodeKey,
            prologue: NodeChannel.prologue
        )
        let first = try handshake.writeMessage()
        return (ControllerChannel(handshake: handshake), first)
    }

    private init(handshake: NoiseHandshake) { self.handshake = handshake }

    /// Reads the node's answer, the channel's first `data`.
    package mutating func finish(_ answer: [UInt8]) throws(NoiseHandshake.Failure) {
        guard var handshake else { throw .finished }
        _ = try handshake.readMessage(answer)
        transport = try handshake.transport()
        self.handshake = nil
    }

    /// Whether the node has answered.
    package var isOpen: Bool { transport != nil }

    /// `message` sealed for the node.
    package mutating func send(_ message: ChannelMessage) throws(NoiseHandshake.Failure) -> [UInt8] {
        guard var transport else { throw .wrongTurn }
        defer { self.transport = transport }
        return try transport.seal(message.bytes)
    }

    /// A node's message, opened and parsed; nil when it opens to something that is not a channel message.
    package mutating func receive(_ data: [UInt8]) throws(NoiseHandshake.Failure) -> ChannelMessage? {
        guard var transport else { throw .wrongTurn }
        defer { self.transport = transport }
        return try? ChannelMessage(parsing: transport.open(data))
    }
}
