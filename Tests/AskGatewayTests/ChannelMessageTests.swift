internal import Testing

@testable import AskGateway

/// Channel messages round-trip, and what the document does not allow is refused: sizes out of 1 to 1,000, empty or control-laden
/// names, invalid UTF-8, unknown kinds.
struct ChannelMessageTests {
    private let size = ChannelMessage.Size(columns: 120, rows: 40)!

    @Test func `every message round-trips`() throws {
        let messages: [ChannelMessage] = [
            .attach(size, session: "20261126T001752Z-80b4ee4f"), .start(size, folder: "/srv/project"),
            .input(Array("\u{1B}[A".utf8)), .resize(size), .output(Array("\u{1B}[?2026h".utf8)),
            .ended("closed at the node"),
            .refused("policy.gatewayStart is off"), .ended("")
        ]
        for message in messages { #expect(try ChannelMessage(parsing: message.bytes) == message) }
    }

    @Test func `what the document does not allow is refused`() {
        #expect(
            ChannelMessage.Size(columns: 0, rows: 10) == nil && ChannelMessage.Size(columns: 10, rows: 1_001) == nil
        )
        #expect(throws: ChannelMessage.Refusal.empty) { try ChannelMessage(parsing: []) }
        #expect(throws: ChannelMessage.Refusal.unknownKind(0x55)) { try ChannelMessage(parsing: [0x55]) }
        #expect(throws: ChannelMessage.Refusal.malformed) { try ChannelMessage(parsing: [0x01, 0, 120, 0, 40]) }
        #expect(throws: ChannelMessage.Refusal.malformed) { try ChannelMessage(parsing: [0x01, 0, 120, 0, 40, 0x0A]) }
        #expect(throws: ChannelMessage.Refusal.malformed) { try ChannelMessage(parsing: [0x01, 0, 0, 0, 40, 0x61]) }
        #expect(throws: ChannelMessage.Refusal.malformed) { try ChannelMessage(parsing: [0x02, 0, 120, 0, 40, 0xFF]) }
        #expect(throws: ChannelMessage.Refusal.malformed) { try ChannelMessage(parsing: [0x04, 0, 120, 0, 40, 1]) }
        #expect(throws: ChannelMessage.Refusal.malformed) { try ChannelMessage(parsing: [0x03]) }
    }

    @Test func `random bytes never crash the parser, and whatever parses re-encodes to itself`() {
        for _ in 0 ..< 20_000 {
            var bytes = (0 ..< Int.random(in: 0 ... 40)).map { _ in UInt8.random(in: 0 ... 255) }
            if !bytes.isEmpty { bytes[0] = [0x01, 0x02, 0x03, 0x04, 0x10, 0x11, 0x12][Int.random(in: 0 ... 6)] }
            if let message = try? ChannelMessage(parsing: bytes) { #expect(message.bytes == bytes) }
        }
    }
}
