import Testing

@testable import AskTUI

/// The middle of a long tool output folds away, keeping its head and tail (roadmap 0078).
@Suite("Long tool output folds its middle")
struct ShownToolOutputTests {
    private func numbered(_ count: Int) -> String { (1 ... count).map { "line \($0)" }.joined(separator: "\n") }

    @Test func `output within both limits is shown whole, with no marker`() {
        let output = numbered(10)
        let shown = ShownToolOutput(output, maxLines: 10, maxBytes: 1000, folded: true)
        #expect(shown.text == output)
        #expect(shown.markerLine == nil)
    }

    @Test func `one line over the limit folds the middle, head and tail sharing the budget`() {
        let shown = ShownToolOutput(numbered(11), maxLines: 10, maxBytes: 1000, folded: true)
        #expect(shown.text == (Array(1 ... 5) + Array(7 ... 11)).map { "line \($0)" }.joined(separator: "\n"))
        #expect(shown.markerLine == 5)
        #expect(shown.hiddenLines == 1)
        #expect(shown.hiddenBytes == "line 6\n".utf8.count)
    }

    @Test func `an odd budget gives the head the extra line`() {
        let shown = ShownToolOutput(numbered(20), maxLines: 5, maxBytes: 1000, folded: true)
        #expect(shown.text == ["line 1", "line 2", "line 3", "line 19", "line 20"].joined(separator: "\n"))
        #expect(shown.markerLine == 3)
        #expect(shown.hiddenLines == 15)
    }

    @Test func `the byte limit folds too, counting UTF-8 bytes`() {
        // Ten lines of "é" twice: 4 bytes each, 5 with the line feed, 49 in all.
        let output = Array(repeating: "éé", count: 10).joined(separator: "\n")
        let shown = ShownToolOutput(output, maxLines: 100, maxBytes: 18, folded: true)
        // 9 bytes for each end: one line of 5 with its line feed; a second would make 10.
        #expect(shown.markerLine == 1)
        #expect(shown.hiddenLines == 8)
        #expect(shown.hiddenBytes == 40)
        #expect(shown.text == "éé\néé")
    }

    @Test func `open, the whole output is shown and the marker stays where the middle starts`() {
        let output = numbered(11)
        let shown = ShownToolOutput(output, maxLines: 10, maxBytes: 1000, folded: false)
        #expect(shown.text == output)
        #expect(shown.markerLine == 5)
        #expect(shown.hiddenLines == 1)
    }

    @Test func `the marker says what is hidden, and how to bring it back`() {
        let folded = ShownToolOutput(numbered(300), maxLines: 10, maxBytes: 100_000, folded: true)
        #expect(folded.marker == "⋯ 290 lines hidden (2 KiB) · click to show")
        let open = ShownToolOutput(numbered(300), maxLines: 10, maxBytes: 100_000, folded: false)
        #expect(open.marker == "⋯ 290 lines shown · click to fold")
        let one = ShownToolOutput(numbered(3), maxLines: 2, maxBytes: 1000, folded: true)
        #expect(one.marker == "⋯ 1 line hidden (7 B) · click to show")
    }

    @Test func `a single line too large for either end is hidden whole`() {
        let line = String(repeating: "x", count: 100)
        let shown = ShownToolOutput(line, maxLines: 10, maxBytes: 50, folded: true)
        #expect(shown.text == "")
        #expect(shown.markerLine == 0)
        #expect(shown.hiddenLines == 1)
        #expect(shown.hiddenBytes == 101)
    }
}
