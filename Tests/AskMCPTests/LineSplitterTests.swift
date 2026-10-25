internal import Testing

@testable import AskMCP

/// Turning a stream of bytes into the lines a stdio server's messages are (ADR-0096): one message a line, however the bytes were chunked.
@Suite("A line splitter makes the same lines from any chunking")
struct LineSplitterTests {
    private func lines(_ chunks: [String], limit: Int = 1 << 20) -> [String] {
        var splitter = LineSplitter(maximumLineBytes: limit)
        return chunks.flatMap { splitter.feed(Array($0.utf8)).map { String(decoding: $0, as: UTF8.self) } }
    }

    @Test func `whole lines come out as they are, without their newlines`() {
        #expect(lines(["one\ntwo\n"]) == ["one", "two"])
    }

    @Test func `a line split across chunks is joined, wherever the split falls`() {
        let whole = "alpha\nbeta\ngamma\n"
        for cut in 1 ..< whole.count {
            let index = whole.index(whole.startIndex, offsetBy: cut)
            #expect(
                lines([String(whole[..<index]), String(whole[index...])]) == ["alpha", "beta", "gamma"], "cut at \(cut)"
            )
        }
    }

    @Test func `one byte at a time makes the same lines`() {
        #expect(lines(Array("a\nbc\n").map(String.init)) == ["a", "bc"])
    }

    @Test func `a carriage return before the newline is not part of the line, and empty lines are not messages`() {
        #expect(lines(["one\r\n\n\r\ntwo\n"]) == ["one", "two"])
    }

    @Test func `text with no newline yet comes out when its newline does`() {
        var splitter = LineSplitter(maximumLineBytes: 100)
        #expect(splitter.feed(Array("partial".utf8)).isEmpty)
        #expect(splitter.feed(Array(" line\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == ["partial line"])
    }

    @Test func `multi-byte characters survive a split in the middle of one`() {
        let bytes = Array("é€😀\n".utf8)
        var splitter = LineSplitter(maximumLineBytes: 100)
        var out: [[UInt8]] = []
        for byte in bytes { out += splitter.feed([byte]) }
        #expect(out.map { String(decoding: $0, as: UTF8.self) } == ["é€😀"])
    }

    @Test func `a line that outgrows the limit is refused, and the splitter says so instead of growing for ever`() {
        var splitter = LineSplitter(maximumLineBytes: 10)
        _ = splitter.feed(Array("0123456789".utf8))
        #expect(!splitter.overflowed)
        _ = splitter.feed(Array("a".utf8))
        #expect(splitter.overflowed)
        #expect(
            splitter.feed(Array("more\nlines\n".utf8)).isEmpty,
            "nothing more is taken from a stream that has gone wrong")
    }

    @Test func `a line exactly at the limit is a line`() {
        #expect(lines(["0123456789\n"], limit: 10) == ["0123456789"])
    }
}
