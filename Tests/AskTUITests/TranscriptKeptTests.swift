import Testing

@testable import AskTUI

/// A tool's output kept for its block, at most ``Transcript/outputLineLimit`` lines (note n47): it was cut by splitting the whole
/// output into lines by `Character`, a tenth of a long session's resume, and an output with CRLF line ends was never cut, as `\r\n`
/// is one `Character` and not `\n`.
@Suite("A tool's output is kept to its line limit, counted by line feeds")
struct TranscriptKeptTests {
    /// What `kept` did before, for text with LF line ends only.
    private static func reference(_ output: String) -> String {
        let text = Transcript.withoutTrailingLineEnds(output)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > Transcript.outputLineLimit else { return String(text) }
        let cut = lines.count - Transcript.outputLineLimit
        return lines.prefix(Transcript.outputLineLimit).joined(separator: "\n") + "\n… \(cut) more lines not shown"
    }

    private static func lines(_ count: Int, _ end: String = "\n") -> String {
        (0 ..< count).map { "line \($0) été 🙂" }.joined(separator: end)
    }

    static let texts = [
        "", "one", "one\n", "one\n\n\n", "\n\none\n\ntwo\n", lines(399), lines(400), lines(401), lines(400) + "\n",
        lines(401) + "\n\n",
        lines(5_000), String(repeating: "\n", count: 900) + "x"
    ]

    @Test(arguments: texts)
    func `LF text is kept as it was`(text: String) {
        #expect(Transcript.kept(text) == Self.reference(text))
    }

    @Test func `CRLF text is cut at the limit too, its line ends kept as written`() {
        let kept = Transcript.kept(Self.lines(5_000, "\r\n") + "\r\n")
        #expect(kept.hasSuffix("\n… 4600 more lines not shown"))
        #expect(kept.utf8.count(where: { $0 == UInt8(ascii: "\n") }) == Transcript.outputLineLimit)
    }
}
