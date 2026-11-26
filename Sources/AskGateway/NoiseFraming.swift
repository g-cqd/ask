/// Noise messages over a byte stream (`docs/protocol/gateway.md`, "Layers"): each message is its length, 2 bytes big-endian, then the
/// message. The reader takes bytes as they arrive, in any pieces, and gives back whole messages.
package struct NoiseFraming: Sendable {
    /// Why a stream was refused.
    package enum Refusal: Error, Equatable { case tooLong }

    private var buffer: [UInt8] = []

    package init() {}

    /// `message` as it goes on the stream.
    package static func frame(_ message: [UInt8]) throws(Refusal) -> [UInt8] {
        guard message.count <= Int(UInt16.max) else { throw .tooLong }
        return RelayBytes.u16(UInt16(message.count)) + message
    }

    /// The whole messages `bytes` completes, in order; what is left of a message waits for the next bytes. At most one message and
    /// its length are ever held, 65,537 bytes, whatever the other side sends.
    package mutating func read(_ bytes: some Collection<UInt8>) -> [[UInt8]] {
        buffer += bytes
        var messages: [[UInt8]] = []
        var start = 0
        while buffer.count - start >= 2 {
            let length = Int(RelayBytes.readU16(buffer[start...]))
            guard buffer.count - start - 2 >= length else { break }
            messages.append(Array(buffer[(start + 2) ..< (start + 2 + length)]))
            start += 2 + length
        }
        buffer.removeFirst(start)
        return messages
    }

    /// Bytes read that do not yet make a whole message.
    package var pending: Int { buffer.count }
}
