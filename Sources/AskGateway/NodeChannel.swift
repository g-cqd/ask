package import CryptoKit

/// A node's side of one end-to-end channel (ADR-0170): it answers a controller's `IK` first message only when the controller's
/// static key is one the node trusts, then opens what the controller sends and seals what it answers. The gateway carries the bytes.
package struct NodeChannel: Sendable {
    /// Why a channel was refused or ended.
    package enum Failure: Error, Equatable {
        /// The controller's key is not one this node trusts.
        case untrusted
        case handshake(NoiseHandshake.Failure)
        case message(ChannelMessage.Refusal)
    }

    /// The prologue every channel is bound to.
    static let prologue = Array("ask-gateway/1 channel".utf8)

    private var transport: NoiseTransport
    /// The controller's static key, as the node checked it.
    package let controller: Curve25519.KeyAgreement.PublicKey

    /// Reads the controller's first message and answers it.
    /// - Parameters:
    ///   - first: the controller's `IK` first message, from the `open` frame.
    ///   - nodeKey: this node's static key.
    ///   - trusts: whether a controller key is trusted, read at this moment, so an untrusted key is refused at once.
    /// - Returns: the channel, and the answer to send as the channel's first `data`.
    /// - Throws: ``Failure/untrusted`` for a key the node does not trust; a handshake failure for a message that does not read.
    package static func accept(
        _ first: [UInt8],
        nodeKey: Curve25519.KeyAgreement.PrivateKey,
        trusts: (Curve25519.KeyAgreement.PublicKey) -> Bool
    ) throws(Failure) -> (channel: NodeChannel, answer: [UInt8]) {
        do {
            var handshake = try NoiseHandshake(pattern: .ik, initiator: false, localStatic: nodeKey, prologue: prologue)
            _ = try handshake.readMessage(first)
            guard let controller = handshake.remoteStatic, trusts(controller) else { throw Failure.untrusted }
            let answer = try handshake.writeMessage()
            return (NodeChannel(transport: try handshake.transport(), controller: controller), answer)
        } catch let failure as NoiseHandshake.Failure {
            throw .handshake(failure)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw .untrusted
        }
    }

    /// A controller's message, opened and parsed.
    package mutating func receive(_ data: [UInt8]) throws(Failure) -> ChannelMessage {
        let opened: [UInt8]
        do { opened = try transport.open(data) } catch { throw .handshake(error) }
        do { return try ChannelMessage(parsing: opened) } catch { throw .message(error) }
    }

    /// `message` sealed for the controller; output too large for one Noise message is split into as many as it needs.
    package mutating func send(_ message: ChannelMessage) throws(Failure) -> [[UInt8]] {
        var pieces: [ChannelMessage] = [message]
        if case .output(let bytes) = message, bytes.count > Self.largestOutput {
            pieces = stride(from: 0, to: bytes.count, by: Self.largestOutput)
                .map { .output(Array(bytes[$0 ..< min($0 + Self.largestOutput, bytes.count)])) }
        }
        var sealed: [[UInt8]] = []
        for piece in pieces {
            do { sealed.append(try transport.seal(piece.bytes)) } catch { throw .handshake(error) }
        }
        return sealed
    }

    /// The most output bytes in one message. A channel's Noise message is a relay frame's body, at most 65,514 bytes; less its
    /// 16-byte tag and the kind byte.
    static let largestOutput = RelayFrame.maximumBody - 16 - 1
}
