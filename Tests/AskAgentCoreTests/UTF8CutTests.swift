import Testing

@testable import AskAgentCore

/// A byte cut through UTF-8 text must not leave half a character at either side of it (roadmap 0057, ADR-0083).
@Suite("A cut through UTF-8 never leaves half a character")
struct UTF8CutTests {
    /// One, two, three and four bytes a character.
    private static let text = "aé€😀z"
    private let bytes = Array(UTF8CutTests.text.utf8)

    private func decodes(_ slice: ArraySlice<UInt8>) -> Bool { String(validating: slice, as: UTF8.self) != nil }

    @Test func `at every cut, both sides are whole text, and no more than three bytes are given up on each`() {
        for cut in 0 ... bytes.count {
            let head = UTF8Cut.droppingPartialEnd(bytes[..<cut])
            let tail = UTF8Cut.droppingPartialStart(bytes[cut...])
            #expect(decodes(head) && decodes(tail), "cut at \(cut)")
            #expect(cut - head.count <= 3 && (bytes.count - cut) - tail.count <= 3, "cut at \(cut)")
            #expect(Array(bytes[..<cut]).starts(with: head) && Array(bytes[cut...]).suffix(tail.count) == Array(tail))
        }
    }

    @Test func `a cut between characters loses nothing`() {
        let boundaries = [0, 1, 3, 6, 10, 11]
        for cut in boundaries {
            #expect(UTF8Cut.droppingPartialEnd(bytes[..<cut]).count == cut, "head at \(cut)")
            #expect(UTF8Cut.droppingPartialStart(bytes[cut...]).count == bytes.count - cut, "tail at \(cut)")
        }
    }

    @Test func `a cut inside a character gives up exactly that character's bytes on the side that holds part of it`() {
        // `€` is bytes 3 ..< 6: cutting at 4 leaves its first byte before the cut and two after.
        #expect(UTF8Cut.droppingPartialEnd(bytes[..<4]).count == 3)
        #expect(UTF8Cut.droppingPartialStart(bytes[4...]).count == bytes.count - 6)
        // `😀` is bytes 6 ..< 10: cutting at 9 leaves three bytes before and one after.
        #expect(UTF8Cut.droppingPartialEnd(bytes[..<9]).count == 6)
        #expect(UTF8Cut.droppingPartialStart(bytes[9...]).count == 1)
    }

    @Test func `bytes that are not text at all are cut without a crash and without inventing anything`() {
        let binary: [UInt8] = [0x80, 0x80, 0x80, 0x80, 0xFF, 0xC3, 0xC3, 0xE2, 0x82]
        for cut in 0 ... binary.count {
            _ = UTF8Cut.droppingPartialEnd(binary[..<cut])
            _ = UTF8Cut.droppingPartialStart(binary[cut...])
        }
        #expect(
            UTF8Cut.droppingPartialStart(binary[...]).count == binary.count - 3,
            "at most three stray continuation bytes go")
        #expect(UTF8Cut.droppingPartialEnd(binary[...]).count == binary.count - 2, "a truncated lead at the end goes")
        #expect(
            UTF8Cut.droppingPartialEnd(ArraySlice<UInt8>()).isEmpty
                && UTF8Cut.droppingPartialStart(ArraySlice<UInt8>()).isEmpty)
    }
}
