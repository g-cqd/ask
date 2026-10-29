import Testing

@testable import AskTUI

/// A folded block's header counts its output's lines without building them (roadmap 0088): the count must be what splitting finds.
@Suite("Counting hard lines agrees with splitting them")
struct HardLineCountTests {
    @Test(arguments: ["", "one", "one\n", "\n\n", "a\tb\nc", "tab\t\tonly", "trailing\n\nlines\n", "é\n日本\n🙂"])
    func `the count is the number of lines the split finds`(text: String) {
        #expect(TranscriptContent.hardLineCount(of: text) == TranscriptContent.hardLines(of: text).count)
    }

    @Test func `tabs still expand to four spaces`() {
        #expect(TranscriptContent.hardLines(of: "a\tb\nc") == ["a    b", "c"])
    }
}
