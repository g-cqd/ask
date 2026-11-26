internal import Testing

@testable import AskGateway

/// The relay frames of `docs/protocol/gateway.md`: each kind round-trips, and parsing refuses what the document does not allow, for
/// any bytes at all.
struct RelayFrameTests {
    private static let ikFirst = [UInt8](repeating: 7, count: 96)

    @Test func `every kind round-trips through its bytes`() throws {
        let frames = [
            try RelayFrame(kind: .hello, body: [0, 1, 2]),
            try RelayFrame(kind: .list, body: [1, 2, 3]),
            try RelayFrame(kind: .lists, body: [UInt8](repeating: 9, count: 32) + [0, 0, 0, 2, 0xAA, 0xBB]),
            try RelayFrame(kind: .open, channel: 3, body: [UInt8](repeating: 1, count: 32) + Self.ikFirst),
            try RelayFrame(kind: .data, channel: 0xFFFF_FFFF, body: [5]),
            try RelayFrame(kind: .close, channel: 3, body: [2] + Array("node gone".utf8)),
            try RelayFrame(kind: .ping, body: [1, 2, 3, 4, 5, 6, 7, 8]),
            try RelayFrame(kind: .pong, body: [1, 2, 3, 4, 5, 6, 7, 8])
        ]
        for frame in frames { #expect(try RelayFrame(parsing: frame.bytes) == frame) }
        #expect(frames[4].bytes.prefix(5) == [0x11, 0xFF, 0xFF, 0xFF, 0xFF])
    }

    @Test func `what the document does not allow is refused`() {
        #expect(throws: RelayFrame.Refusal.tooShort) { try RelayFrame(parsing: [0x01, 0, 0, 0]) }
        #expect(throws: RelayFrame.Refusal.unknownKind(0x7F)) { try RelayFrame(parsing: [0x7F, 0, 0, 0, 0]) }
        #expect(throws: RelayFrame.Refusal.wrongChannel) { try RelayFrame(kind: .data, channel: 0, body: [1]) }
        #expect(throws: RelayFrame.Refusal.wrongChannel) {
            try RelayFrame(kind: .ping, channel: 1, body: [UInt8](repeating: 0, count: 8))
        }
        #expect(throws: RelayFrame.Refusal.malformedBody) { try RelayFrame(kind: .hello, body: [0, 1, 3]) }
        #expect(throws: RelayFrame.Refusal.malformedBody) { try RelayFrame(kind: .open, channel: 1, body: [1, 2]) }
        #expect(throws: RelayFrame.Refusal.malformedBody) { try RelayFrame(kind: .close, channel: 1, body: [9]) }
        #expect(throws: RelayFrame.Refusal.malformedBody) { try RelayFrame(kind: .close, channel: 1, body: [0, 0xFF]) }
        #expect(throws: RelayFrame.Refusal.malformedBody) {
            try RelayFrame(kind: .lists, body: [UInt8](repeating: 9, count: 32) + [0, 0, 0, 5, 1])
        }
        #expect(throws: RelayFrame.Refusal.tooLong) {
            try RelayFrame(kind: .data, channel: 1, body: [UInt8](repeating: 0, count: RelayFrame.maximumBody + 1))
        }
    }

    @Test func `random bytes never crash the parser, and whatever parses re-encodes to itself`() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 20_000 {
            let length = Int.random(in: 0 ... 140, using: &generator)
            var bytes = (0 ..< length).map { _ in UInt8.random(in: 0 ... 255, using: &generator) }
            // Bias the first byte to real kinds, so the shape checks are reached.
            if !bytes.isEmpty { bytes[0] = [0x01, 0x02, 0x03, 0x10, 0x11, 0x12, 0x20, 0x21, bytes[0]].randomElement()! }
            if let frame = try? RelayFrame(parsing: bytes) { #expect(frame.bytes == bytes) }
        }
    }
}
