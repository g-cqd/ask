import Testing

@testable import AskAI

/// Server-sent events, framed per the WHATWG specification, decoded incrementally from arbitrary chunks.
@Suite("SSE decoding is incremental, spec-framed, and bounded")
struct SSEDecoderTests {
    private func decode(_ chunks: [String], limits: SSEDecoder.Limits = .standard) throws -> [SSEEvent] {
        var decoder = SSEDecoder(limits: limits)
        var events: [SSEEvent] = []
        for chunk in chunks {
            let bytes = Array(chunk.utf8)
            try decoder.feed(bytes.span, into: &events)
        }
        return events
    }

    private func event(_ name: String, _ data: String) -> SSEEvent { SSEEvent(name: name, data: Array(data.utf8)) }

    @Test func `an event is dispatched at the blank line`() throws {
        #expect(try decode(["event: ping\ndata: {}\n\n"]) == [event("ping", "{}")])
        #expect(try decode(["event: ping\ndata: {}\n"]).isEmpty)
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func `every line ending frames the same events`(ending: String) throws {
        let stream = ["event: a", "data: 1", "", "data: 2", "", ""].joined(separator: ending)
        #expect(try decode([stream]) == [event("a", "1"), event("message", "2")])
    }

    @Test func `splitting the stream at any byte yields the same events`() throws {
        let stream = "\u{FEFF}event: a\r\ndata: x\r\n\r\n: comment\ndata: é\ndata: 本\n\nevent: b\rdata: y\r\r"
        let whole = try decode([stream])
        #expect(whole == [event("a", "x"), event("message", "é\n本"), event("b", "y")])
        let bytes = Array(stream.utf8)
        for cut in 0 ... bytes.count {
            var decoder = SSEDecoder()
            var events: [SSEEvent] = []
            try decoder.feed(Array(bytes[..<cut]).span, into: &events)
            try decoder.feed(Array(bytes[cut...]).span, into: &events)
            #expect(events == whole, "cut at \(cut)")
        }
    }

    @Test func `data lines are joined with a line feed`() throws {
        #expect(try decode(["data: one\ndata: two\ndata:\n\n"]) == [event("message", "one\ntwo\n")])
    }

    @Test func `only one space after the colon is stripped`() throws {
        #expect(
            try decode(["data:  two spaces\n\n", "data:none\n\n"]) == [
                event("message", " two spaces"), event("message", "none")
            ])
    }

    @Test func `comments, unknown fields and fields without a value are ignored`() throws {
        #expect(try decode([": keep-alive\nid: 7\nretry: 10\nunknown: x\ndata\n\n"]) == [event("message", "")])
    }

    @Test func `a blank line without data dispatches nothing and resets the name`() throws {
        #expect(try decode(["event: lost\n\ndata: kept\n\n"]) == [event("message", "kept")])
    }

    @Test func `a byte order mark is dropped only at the start of the stream`() throws {
        #expect(try decode(["\u{FEFF}data: a\n\n"]) == [event("message", "a")])
        #expect(try decode(["\u{FEFF}", "data: a\n\n"]) == [event("message", "a")])
        // Later, the same bytes are part of a field name, which then matches nothing.
        #expect(try decode(["data: a\n\n\u{FEFF}data: b\n\n"]) == [event("message", "a")])
    }

    @Test func `an event larger than the limit is refused`() throws {
        let limits = SSEDecoder.Limits(maximumEventBytes: 16)
        #expect(throws: SSEError.eventTooLarge(limit: 16)) {
            _ = try decode(["data: " + String(repeating: "x", count: 32)], limits: limits)
        }
        #expect(throws: SSEError.eventTooLarge(limit: 16)) {
            _ = try decode(["data: 0123456789\n", "data: 0123456789\n"], limits: limits)
        }
        #expect(try decode(["data: 0123456789\n\n"], limits: limits) == [event("message", "0123456789")])
    }

    @Test func `the end of the stream reports an unterminated event`() throws {
        var decoder = SSEDecoder()
        var events: [SSEEvent] = []
        try decoder.feed(Array("data: done\n\ndata: cut".utf8).span, into: &events)
        #expect(decoder.finish() == .unterminatedEvent)
        var dangling = SSEDecoder()
        try dangling.feed(Array("data: whole line, no blank line\n".utf8).span, into: &events)
        #expect(dangling.finish() == .unterminatedEvent)
        var clean = SSEDecoder()
        try clean.feed(Array("data: done\n\n".utf8).span, into: &events)
        #expect(clean.finish() == .complete)
    }
}
