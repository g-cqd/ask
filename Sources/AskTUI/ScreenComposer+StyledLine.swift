internal import TerminalKitMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// A row of rendered Markdown as a transcript row: its runs' styles become accents, their hyperlinks links, and the source they name the
    /// segments a selection maps through, so what is copied is the Markdown the row shows (roadmap 0065).
    static func line(of row: StyledLine, block: Int, inset: Int, source: inout MarkdownSourceLines) -> Line {
        var line = Line(text: String(repeating: " ", count: inset) + row.text, style: .default)
        var column = inset
        for run in row.runs {
            let width = UnicodeWidth.displayWidth(of: run.text)
            defer { column += width }
            var look = run.style
            let uri = look.link
            look.link = nil
            if width > 0, look != .default {
                line.accents.append(Accent(columns: column ..< column + width, style: look))
            }
            if width > 0, let uri { line.links.append(PathLinks.Link(columns: column ..< column + width, uri: uri)) }
            if let range = run.source {
                add(range, of: run.text, at: column, to: &line.segments, source: &source)
            }
        }
        line.accents = merged(line.accents, columns: \.columns) { $0.style == $1.style }
        line.links = merged(line.links, columns: \.columns) { $0.uri == $1.uri }
        if let first = line.segments.first {
            line.source = Source(
                block: block, line: first.line, offset: first.firstOffset, col: first.col, text: first.text)
        }
        return line
    }

    /// Adds the segment for a run that shows the source bytes `range`, joined to the one before when both draw their source as written and
    /// follow each other on the row and in the line. A run that shows no grapheme of its line (a soft break drawn as a space) is chrome.
    private static func add(
        _ range: Range<Int>, of text: String, at column: Int, to segments: inout [RowSegment],
        source: inout MarkdownSourceLines
    ) {
        let start = source.position(of: range.lowerBound)
        let count = source.count(on: start.line, from: range.lowerBound, to: range.upperBound)
        guard count > 0 else { return }
        let segment = RowSegment(
            line: start.line, firstOffset: start.offset, col: column, text: text, sourceCount: count)
        if let last = segments.last, last.isLinear, segment.isLinear, last.line == segment.line,
            last.firstOffset + last.sourceCount == segment.firstOffset,
            last.col + UnicodeWidth.displayWidth(of: last.text) == column
        {
            segments[segments.count - 1].text += text
            segments[segments.count - 1].sourceCount += count
        } else {
            segments.append(segment)
        }
    }

    /// Runs of columns with the same look joined where one ends at the next one's start.
    private static func merged<Run>(
        _ runs: [Run], columns: WritableKeyPath<Run, Range<Int>>, same: (Run, Run) -> Bool
    ) -> [Run] {
        var result: [Run] = []
        for run in runs {
            if let last = result.last, last[keyPath: columns].upperBound == run[keyPath: columns].lowerBound,
                same(last, run)
            {
                result[result.count - 1][keyPath: columns] =
                    last[keyPath: columns].lowerBound ..< run[keyPath: columns].upperBound
            } else {
                result.append(run)
            }
        }
        return result
    }
}
