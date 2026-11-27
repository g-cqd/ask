package import CryptoKit

/// Relay frames over a byte stream, inside Noise `XX` (`docs/protocol/gateway.md`, "Layers"): between a node and the gateway. Each
/// side proves its static key in the handshake; the node refuses a gateway whose key is not the one it pinned before it sends its
/// own, and the gateway refuses a node it has not enrolled.
package actor NoiseLink {
    /// Why a link could not be made, or ended.
    package enum Failure: Error, Equatable {
        /// The other side's key is not the one expected.
        case wrongKey
        case ended
        case handshake(NoiseHandshake.Failure)
        case frame(RelayFrame.Refusal)
    }

    /// The prologue the node and the gateway agree on.
    static let prologue = Array("ask-gateway/1 node".utf8)

    private let stream: any ByteStream
    /// Sealed messages, in the order their nonces were used, for the one task that writes them.
    private let outgoing: AsyncStream<[UInt8]>.Continuation
    private let writer: Task<Void, Never>
    private var transport: NoiseTransport
    private var framing: NoiseFraming
    private var waiting: [[UInt8]]
    /// The other side's static key, as its handshake proved it.
    package nonisolated let remoteKey: Curve25519.KeyAgreement.PublicKey

    private init(
        stream: any ByteStream,
        transport: NoiseTransport,
        framing: NoiseFraming,
        waiting: [[UInt8]],
        remoteKey: Curve25519.KeyAgreement.PublicKey
    ) {
        self.stream = stream
        self.transport = transport
        self.framing = framing
        self.waiting = waiting
        self.remoteKey = remoteKey
        let (queue, outgoing) = AsyncStream<[UInt8]>.makeStream()
        self.outgoing = outgoing
        // One writer: two sends at once must reach the wire in the order they were sealed, or the other side's nonce is wrong.
        writer = OrderedWriter.start(queue, to: stream)
    }

    /// The node's side: connects as the initiator and stops, before sending its own key, unless the gateway proves `gatewayKey`.
    package static func node(
        over stream: any ByteStream,
        key: Curve25519.KeyAgreement.PrivateKey,
        gatewayKey: Curve25519.KeyAgreement.PublicKey
    ) async throws(Failure) -> NoiseLink {
        try await handshake(over: stream, initiator: true, key: key) {
            $0.rawRepresentation == gatewayKey.rawRepresentation
        }
    }

    /// The gateway's side: answers as the responder, and keeps the link only for a node whose key `enrolled` accepts.
    package static func gateway(
        over stream: any ByteStream,
        key: Curve25519.KeyAgreement.PrivateKey,
        enrolled: @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool
    ) async throws(Failure) -> NoiseLink {
        try await handshake(over: stream, initiator: false, key: key, accepts: enrolled)
    }

    /// Sends one frame: sealed now, in the order sends are made, and written by the link's one writer in that order.
    package func send(_ frame: RelayFrame) throws(Failure) {
        do {
            let bytes = try NoiseFraming.frame(try transport.seal(frame.bytes))
            if case .terminated = outgoing.yield(bytes) { throw Failure.ended }
        } catch let failure as NoiseHandshake.Failure {
            throw .handshake(failure)
        } catch {
            throw .ended
        }
    }

    /// The next frame; nil once the stream has ended. A frame that does not open or parse ends the link. One task receives.
    package func receive() async throws(Failure) -> RelayFrame? {
        while waiting.isEmpty {
            let piece: [UInt8]?
            do { piece = try await stream.receive() } catch { throw .ended }
            guard let piece else { return nil }
            waiting += framing.read(piece)
        }
        let message = waiting.removeFirst()
        let opened: [UInt8]
        do { opened = try transport.open(message) } catch { throw .handshake(error) }
        do { return try RelayFrame(parsing: opened) } catch { throw .frame(error) }
    }

    /// Ends the link, once what was sent before has been written.
    package func close() async {
        outgoing.finish()
        await writer.value
        await stream.close()
    }

    private static func handshake(
        over stream: any ByteStream,
        initiator: Bool,
        key: Curve25519.KeyAgreement.PrivateKey,
        accepts: @Sendable (Curve25519.KeyAgreement.PublicKey) -> Bool
    ) async throws(Failure) -> NoiseLink {
        var framing = NoiseFraming()
        var waiting: [[UInt8]] = []
        do {
            var handshake = try NoiseHandshake(pattern: .xx, initiator: initiator, localStatic: key, prologue: prologue)
            while !handshake.isComplete {
                if handshake.writesNext {
                    // The initiator's last message carries its own key: it goes only to a responder that proved the right one.
                    if initiator, let remote = handshake.remoteStatic, !accepts(remote) { throw Failure.wrongKey }
                    try await stream.send(try NoiseFraming.frame(try handshake.writeMessage()))
                } else {
                    guard let message = try await nextMessage(stream, &framing, &waiting) else { throw Failure.ended }
                    _ = try handshake.readMessage(message)
                }
            }
            guard let remote = handshake.remoteStatic, accepts(remote) else { throw Failure.wrongKey }
            return NoiseLink(
                stream: stream,
                transport: try handshake.transport(),
                framing: framing,
                waiting: waiting,
                remoteKey: remote
            )
        } catch let failure as Failure {
            await stream.close()
            throw failure
        } catch let failure as NoiseHandshake.Failure {
            await stream.close()
            throw .handshake(failure)
        } catch {
            await stream.close()
            throw .ended
        }
    }

    /// The next whole Noise message from `stream`, reading as many pieces as it takes.
    private static func nextMessage(
        _ stream: any ByteStream,
        _ framing: inout NoiseFraming,
        _ waiting: inout [[UInt8]]
    ) async throws(Failure) -> [UInt8]? {
        while waiting.isEmpty {
            let piece: [UInt8]?
            do { piece = try await stream.receive() } catch { throw .ended }
            guard let piece else { return nil }
            waiting += framing.read(piece)
        }
        return waiting.removeFirst()
    }
}
