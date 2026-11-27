internal import Testing

@testable import AskGateway

/// The controllers' door speaks WebSocket (RFC 6455): its handshake matches the RFC's own example, a request that is not a version 13
/// WebSocket is refused, and frames are read as the RFC says, masked and in pieces, fragmented or not, with text and oversize refused.
struct WebSocketTests {
    private static func request(_ extra: String = "", version: String = "13") -> [UInt8] {
        Array(
            ("GET /socket HTTP/1.1\r\nHost: gateway.example\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\n"
                + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: \(version)\r\n\(extra)\r\n")
                .utf8
        )
    }

    /// A client frame: masked, as a client must send it.
    private static func clientFrame(_ opcode: UInt8, _ payload: [UInt8], final: Bool = true) -> [UInt8] {
        let mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]
        var out: [UInt8] = [(final ? 0x80 : 0) | opcode]
        if payload.count < 126 {
            out.append(0x80 | UInt8(payload.count))
        } else {
            out += [0x80 | 126, UInt8(payload.count >> 8), UInt8(truncatingIfNeeded: payload.count)]
        }
        return out + mask + payload.enumerated().map { $1 ^ mask[$0 % 4] }
    }

    @Test func `the handshake answers as the RFC's example does`() throws {
        #expect(WebSocketHandshake.accept(for: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
        let bytes = Self.request("Cf-Access-Jwt-Assertion: abc\r\n") + [0x81]
        let (handshake, length) = try WebSocketHandshake.parse(bytes)
        #expect(length == bytes.count - 1 && handshake.path == "/socket")
        #expect(handshake.headers["cf-access-jwt-assertion"] == "abc")
        #expect(
            String(decoding: handshake.answer, as: UTF8.self)
                .contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
        )
    }

    @Test func `what is not a version 13 WebSocket opening is refused`() {
        #expect(throws: WebSocketHandshake.Refusal.incomplete) {
            try WebSocketHandshake.parse(Array(Self.request().dropLast(2)))
        }
        #expect(throws: WebSocketHandshake.Refusal.wrongVersion) {
            try WebSocketHandshake.parse(Self.request(version: "8"))
        }
        #expect(throws: WebSocketHandshake.Refusal.notAWebSocket) {
            try WebSocketHandshake.parse(Array("POST / HTTP/1.1\r\nHost: x\r\n\r\n".utf8))
        }
        #expect(throws: WebSocketHandshake.Refusal.tooLarge) {
            try WebSocketHandshake.parse(Array("GET / HTTP/1.1\r\nX: \(String(repeating: "a", count: 20_000))".utf8))
        }
    }

    @Test func `frames are read masked, in pieces, and fragmented`() throws {
        var frames = WebSocketFrames()
        let payload = (0 ..< 300).map { UInt8(truncatingIfNeeded: $0) }
        let stream =
            Self.clientFrame(0x2, Array(payload.prefix(100)), final: false)
            + Self.clientFrame(0x0, Array(payload.dropFirst(100)))
            + Self.clientFrame(0x9, [1, 2]) + Self.clientFrame(0x8, [0x03, 0xE8])
        var messages: [WebSocketFrames.Incoming] = []
        for byte in stream { messages += try frames.read([byte]) }
        #expect(messages == [.binary(payload), .ping([1, 2]), .close(1_000)])
    }

    @Test func `text, an unmasked frame, and a message too large are refused`() {
        var text = WebSocketFrames()
        #expect(throws: WebSocketFrames.Violation.unacceptable) {
            try text.read(Self.clientFrame(0x1, Array("hi".utf8)))
        }
        var unmasked = WebSocketFrames()
        #expect(throws: WebSocketFrames.Violation.protocolError) { try unmasked.read([0x82, 0x01, 0x00]) }
        var large = WebSocketFrames()
        #expect(throws: WebSocketFrames.Violation.tooLarge) { try large.read([0x82, 0xFF, 0, 0, 0, 0, 0, 1, 0, 0]) }
    }

    @Test func `server frames are unmasked, with the length as long as it needs`() {
        #expect(WebSocketFrames.binary([1, 2, 3]) == [0x82, 3, 1, 2, 3])
        #expect(WebSocketFrames.binary([UInt8](repeating: 0, count: 300)).prefix(4) == [0x82, 126, 0x01, 0x2C])
        #expect(
            WebSocketFrames.binary([UInt8](repeating: 0, count: 70_000)).prefix(10) == [
                0x82, 127, 0, 0, 0, 0, 0, 1, 0x11, 0x70
            ]
        )
        #expect(WebSocketFrames.close(1_000) == [0x88, 2, 0x03, 0xE8])
    }
}
