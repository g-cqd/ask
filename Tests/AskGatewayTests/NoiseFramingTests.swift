internal import Testing

@testable import AskGateway

/// Noise messages over a stream: whatever the pieces the bytes arrive in, the same messages come out, in order.
struct NoiseFramingTests {
    @Test func `messages come out whole however the stream is cut`() throws {
        let messages: [[UInt8]] = [[], [1], Array(repeating: 7, count: 300), Array(repeating: 9, count: 65_535)]
        let stream = try messages.flatMap { try NoiseFraming.frame($0) }
        for piece in [1, 2, 3, 5_000, stream.count] {
            var reader = NoiseFraming()
            var out: [[UInt8]] = []
            var offset = 0
            while offset < stream.count {
                out += reader.read(stream[offset ..< min(offset + piece, stream.count)])
                offset += piece
            }
            #expect(out == messages && reader.pending == 0, "pieces of \(piece)")
        }
    }

    @Test func `a message too long for the length is refused`() {
        #expect(throws: NoiseFraming.Refusal.tooLong) { try NoiseFraming.frame([UInt8](repeating: 0, count: 65_536)) }
    }
}
