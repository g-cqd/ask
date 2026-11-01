internal import TerminalKitText

/// A transcript row's source segments as its runs are converted (roadmap 0065, 0152): a run's segment joins the one before when both
/// draw their source as written and follow each other on the row and in the line. The last one's end column and linearity are carried,
/// so a row's segment is not measured again for every run joined to it.
struct RowSegments {
    private(set) var segments: [RowSegment] = []
    private var end: SegmentEnd?

    /// Adds the segment for a run `width` columns wide at `column`, showing the source bytes `range`. A run that shows no grapheme of
    /// its line (a soft break drawn as a space) is chrome.
    mutating func add(
        _ range: Range<Int>,
        of text: String,
        at column: Int,
        width: Int,
        source: inout MarkdownSourceLines
    ) {
        let start = source.position(of: range.lowerBound)
        let count = source.count(on: start.line, from: range.lowerBound, to: range.upperBound)
        guard count > 0 else { return }
        let segment = RowSegment(
            line: start.line,
            firstOffset: start.offset,
            col: column,
            text: text,
            sourceCount: count
        )
        let ascii = SegmentEnd.isPrintableASCII(text)
        let linear = ascii ? text.utf8.count == count : segment.isLinear
        if let end, let previous = segments.last, end.isLinear, linear, previous.line == segment.line,
            previous.firstOffset + previous.sourceCount == segment.firstOffset, end.column == column
        {
            segments[segments.count - 1].text += text
            segments[segments.count - 1].sourceCount += count
            let joined = segments[segments.count - 1]
            // Two runs of printable ASCII join without a grapheme across them; anything else is counted again.
            self.end =
                end.isASCII && ascii
                ? SegmentEnd(column: column + width, isLinear: true, isASCII: true)
                : SegmentEnd(
                    column: joined.col + UnicodeWidth.displayWidth(of: joined.text),
                    isLinear: joined.isLinear,
                    isASCII: false
                )
        } else {
            segments.append(segment)
            end = SegmentEnd(column: column + UnicodeWidth.displayWidth(of: text), isLinear: linear, isASCII: ascii)
        }
    }
}
