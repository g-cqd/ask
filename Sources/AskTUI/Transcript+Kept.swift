/// A tool's output as its block keeps it (note n47).
extension Transcript {
    /// What block `index` keeps of `output`: its escapes read into ``outputSpans`` and removed (note n30), then ``kept(_:)``.
    mutating func keep(_ output: String, at index: Int) -> String {
        let read = OutputEscapes(output)
        let spans = read.lines.prefix(Self.outputLineLimit)
        outputSpans[index] = spans.contains { !$0.isEmpty } ? Array(spans) : nil
        return Self.kept(read.text)
    }

    /// The output without its trailing line feeds, and at most ``outputLineLimit`` lines, with the cut said. Lines are counted by
    /// their line feeds, read as bytes: splitting the output by `Character` cost a tenth of a long session's resume, and never cut CRLF
    /// text, whose `\r\n` is one `Character` (note n47).
    static func kept(_ output: String) -> String {
        let text = withoutTrailingLineEnds(output)
        var feeds = 0
        var cut = text.endIndex
        for index in text.utf8.indices where text.utf8[index] == UInt8(ascii: "\n") {
            feeds += 1
            if feeds == outputLineLimit { cut = index }
        }
        guard feeds >= outputLineLimit else { return String(text) }
        // The last kept line's own carriage return goes, or it would join the note's line feed into one `\r\n`.
        if cut > text.startIndex, text.utf8[text.utf8.index(before: cut)] == UInt8(ascii: "\r") {
            cut = text.utf8.index(before: cut)
        }
        return String(text[..<cut]) + "\n… \(feeds + 1 - outputLineLimit) more lines not shown"
    }

    /// `output` without the line ends at its end.
    static func withoutTrailingLineEnds(_ output: String) -> Substring {
        var text = Substring(output)
        while let last = text.last, last == "\n" || last == "\r\n" || last == "\r" { text = text.dropLast() }
        return text
    }
}
