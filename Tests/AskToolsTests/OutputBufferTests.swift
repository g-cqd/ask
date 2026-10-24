import Foundation
import Testing

@testable import AskTools

/// Found by modelling `OutputBuffer` in Lean (`docs/formal/lean/OutputBuffer.lean`). Its head and tail are what a
/// stream's ends were; `kept` joins them, and `Job.wait(for:)` searches `kept` for a text. Where bytes were omitted
/// the join is not what the command printed, so a text can be found that the command never printed.
@Suite("The bounded output buffer keeps the ends of a stream and says what it dropped")
struct OutputBufferTests {
    private func buffer(_ text: String, keeping: Int) -> OutputBuffer {
        var buffer = OutputBuffer(keeping: keeping)
        buffer.append(Array(text.utf8))
        return buffer
    }

    @Test(arguments: [(0, 0), (3, 5), (8, 8), (9, 8), (40, 8)])
    func `a stream no longer than twice the limit is kept whole, and a longer one loses exactly the excess`(
        length: Int, keeping: Int
    ) {
        let stream = String((0 ..< length).map { Character(UnicodeScalar(UInt8(97 + $0 % 26))) })
        let kept = buffer(stream, keeping: keeping)
        #expect(kept.omitted == Swift.max(0, length - 2 * keeping))
        #expect(kept.kept.count == Swift.min(length, 2 * keeping))
        #expect(Array(stream.utf8).prefix(keeping) == kept.kept.prefix(keeping))
        #expect(Array(stream.utf8).suffix(Swift.min(length, keeping)) == kept.kept.suffix(Swift.min(length, keeping)))
    }

    @Test func `feeding a stream in pieces keeps what feeding it whole keeps`() {
        let stream = String(repeating: "abcdefghij", count: 5)
        var pieces = OutputBuffer(keeping: 7)
        for chunk in stride(from: 0, to: stream.utf8.count, by: 3) {
            pieces.append(Array(stream.utf8.dropFirst(chunk).prefix(3)))
        }
        let whole = buffer(stream, keeping: 7)
        #expect(pieces.kept == whole.kept && pieces.omitted == whole.omitted)
    }

    @Test func `text printed across the omitted middle is not found`() {
        // The stream is `abRe` + 8 bytes that were dropped + `adcd`: it never contains `Read`.
        let stream = "abRe" + "zzzzzzzz" + "adcd"
        let kept = buffer(stream, keeping: 4)
        #expect(!stream.contains("Read"))
        #expect(
            !kept.contains(Array("Read".utf8)), "the head and the tail are not adjacent, so a text cannot span them")
    }

    @Test func `text inside the head, or inside the tail, is found whether or not bytes were omitted`() {
        let kept = buffer("Head" + "zzzzzzzz" + "Tail", keeping: 4)
        #expect(kept.omitted == 8)
        #expect(
            kept.contains(Array("Head".utf8)) && kept.contains(Array("ead".utf8)) && kept.contains(Array("Tail".utf8)))
        #expect(!kept.contains(Array("zz".utf8)), "what was dropped is not there to find")
    }

    @Test
    func `text across the join of a stream nothing was omitted from is found, because there the join is the stream`() {
        let whole = buffer("abReadcd", keeping: 4)
        #expect(whole.omitted == 0 && whole.contains(Array("Read".utf8)))
        let shorter = buffer("abRead", keeping: 4)
        #expect(shorter.contains(Array("Read".utf8)))
    }

    @Test func `a needle that is empty is never found, and one longer than either end is found only whole`() {
        let kept = buffer("abcd" + "zz" + "wxyz", keeping: 4)
        #expect(!kept.contains([]))
        #expect(!kept.contains(Array("abcdw".utf8)) && kept.contains(Array("abcd".utf8)))
    }

    @Test func `a stream of valid UTF-8 is not shown with replacement characters where it was cut`() {
        // Each `é` is two bytes; keeping 3 bytes at each end cuts one in the middle.
        let kept = buffer(String(repeating: "é", count: 10), keeping: 3)
        withKnownIssue("the cut falls inside a character and the text shows U+FFFD") {
            #expect(!kept.text.contains("\u{FFFD}"))
        }
    }
}
