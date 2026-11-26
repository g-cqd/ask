/// A Noise channel's two directions once its handshake is through (section 5.2, `Split()`).
package struct NoiseTransport: Sendable {
    private var sending: NoiseCipherState
    private var receiving: NoiseCipherState
    /// The handshake's hash, the same on both sides: what a higher layer binds to the channel.
    package let handshakeHash: [UInt8]

    init(sending: NoiseCipherState, receiving: NoiseCipherState, handshakeHash: [UInt8]) {
        self.sending = sending
        self.receiving = receiving
        self.handshakeHash = handshakeHash
    }

    /// `plaintext` sealed for the other side, at most 65,519 bytes so the message fits Noise's 65,535.
    package mutating func seal(_ plaintext: [UInt8]) throws(NoiseHandshake.Failure) -> [UInt8] {
        guard plaintext.count <= 65_519 else { throw .malformed }
        do { return try sending.encrypt(plaintext, ad: []) } catch { throw .cipher(error) }
    }

    /// A message from the other side, opened.
    package mutating func open(_ message: [UInt8]) throws(NoiseHandshake.Failure) -> [UInt8] {
        do { return try receiving.decrypt(message, ad: []) } catch { throw .cipher(error) }
    }
}
