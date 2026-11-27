/// WebSocket frames (RFC 6455, section 5) as the gateway's controllers' door reads and writes them: a client's frames must be masked,
/// a message is at most one relay frame long, and only binary messages, pings, pongs and a close are taken; text is refused.
package struct WebSocketFrames: Sendable {
    /// What a client sent.
    package enum Incoming: Sendable, Equatable {
        case binary([UInt8])
        case ping([UInt8])
        case pong
        /// The client closes; its status code, when it gave one.
        case close(UInt16?)
    }

    /// Why the connection must end, with the status a close frame says.
    package enum Violation: Error, Equatable {
        /// An unmasked client frame, a reserved bit or opcode, a control frame fragmented or too long, or a continuation out of
        /// place: 1002.
        case protocolError
        /// A text message: 1003.
        case unacceptable
        /// A message longer than the largest relay frame: 1009.
        case tooLarge

        package var status: UInt16 {
            switch self {
                case .protocolError: 1_002
                case .unacceptable: 1_003
                case .tooLarge: 1_009
            }
        }
    }

    /// The largest message taken: a whole relay frame.
    package static let largestMessage = 5 + RelayFrame.maximumBody

    private var buffer: [UInt8] = []
    private var fragments: [UInt8]?

    package init() {}

    /// The whole messages `bytes` completes, in order; what is left waits for the next bytes.
    package mutating func read(_ bytes: some Collection<UInt8>) throws(Violation) -> [Incoming] {
        buffer += bytes
        var messages: [Incoming] = []
        while let (frame, length) = try next() {
            buffer.removeFirst(length)
            if let message = try take(frame) { messages.append(message) }
        }
        return messages
    }

    /// A binary message from the server: one frame, unmasked.
    package static func binary(_ payload: [UInt8]) -> [UInt8] { frame(opcode: 0x2, payload) }

    /// A pong answering a ping's payload.
    package static func pong(_ payload: [UInt8]) -> [UInt8] { frame(opcode: 0xA, payload) }

    /// A close frame with `status`.
    package static func close(_ status: UInt16) -> [UInt8] {
        frame(opcode: 0x8, [UInt8(status >> 8), UInt8(truncatingIfNeeded: status)])
    }

    private static func frame(opcode: UInt8, _ payload: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x80 | opcode]
        switch payload.count {
            case 0 ..< 126: out.append(UInt8(payload.count))
            case 126 ... 0xFFFF: out += [126] + RelayBytes.u16(UInt16(payload.count))
            default: out += [127] + RelayBytes.u32(0) + RelayBytes.u32(UInt32(payload.count))
        }
        return out + payload
    }

    private struct Frame {
        let final: Bool
        let opcode: UInt8
        let payload: [UInt8]
    }

    /// The next whole frame in the buffer, and its length; nil while it is not whole.
    private func next() throws(Violation) -> (Frame, Int)? {
        guard buffer.count >= 2 else { return nil }
        let first = buffer[0]
        let second = buffer[1]
        guard first & 0x70 == 0, second & 0x80 != 0 else { throw .protocolError }
        var length = Int(second & 0x7F)
        var offset = 2
        if length == 126 {
            guard buffer.count >= 4 else { return nil }
            length = Int(RelayBytes.readU16(buffer.dropFirst(2)))
            offset = 4
        } else if length == 127 {
            guard buffer.count >= 10 else { return nil }
            guard buffer[2 ..< 6].allSatisfy({ $0 == 0 }) else { throw .tooLarge }
            length = Int(RelayBytes.readU32(buffer.dropFirst(6)))
            offset = 10
        }
        guard length <= Self.largestMessage else { throw .tooLarge }
        guard buffer.count >= offset + 4 + length else { return nil }
        let mask = Array(buffer[offset ..< offset + 4])
        let payload = buffer[(offset + 4) ..< (offset + 4 + length)].enumerated().map { $1 ^ mask[$0 % 4] }
        return (Frame(final: first & 0x80 != 0, opcode: first & 0x0F, payload: payload), offset + 4 + length)
    }

    private mutating func take(_ frame: Frame) throws(Violation) -> Incoming? {
        switch frame.opcode {
            case 0x8, 0x9, 0xA:
                guard frame.final, frame.payload.count <= 125 else { throw .protocolError }
                if frame.opcode == 0x9 { return .ping(frame.payload) }
                if frame.opcode == 0xA { return .pong }
                return .close(frame.payload.count >= 2 ? RelayBytes.readU16(frame.payload) : nil)
            case 0x1: throw .unacceptable
            case 0x2:
                guard fragments == nil else { throw .protocolError }
                if frame.final { return .binary(frame.payload) }
                fragments = frame.payload
                return nil
            case 0x0:
                guard var collected = fragments else { throw .protocolError }
                collected += frame.payload
                guard collected.count <= Self.largestMessage else { throw .tooLarge }
                if frame.final {
                    fragments = nil
                    return .binary(collected)
                }
                fragments = collected
                return nil
            default: throw .protocolError
        }
    }
}
