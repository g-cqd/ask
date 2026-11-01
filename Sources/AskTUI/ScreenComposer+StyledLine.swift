internal import TerminalKitMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// A row of rendered Markdown as a transcript row: its runs' styles become accents, their hyperlinks links, and the source they name the
    /// segments a selection maps through, so what is copied is the Markdown the row shows (roadmap 0065).
    static func line(of row: StyledLine, block: Int, inset: Int, source: inout MarkdownSourceLines) -> Line {
        // The text is gathered with the runs rather than joined from them first.
        var text = String(repeating: " ", count: inset)
        var line = Line(text: "", style: .default)
        var column = inset
        var segments = RowSegments()
        for run in row.runs {
            text += run.text
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
                segments.add(range, of: run.text, at: column, width: width, source: &source)
            }
        }
        line.text = text
        line.segments = segments.segments
        line.accents = merged(line.accents, columns: \.columns) { $0.style == $1.style }
        line.links = merged(line.links, columns: \.columns) { $0.uri == $1.uri }
        if let first = line.segments.first {
            line.source = Source(
                block: block,
                line: first.line,
                offset: first.firstOffset,
                col: first.col,
                text: first.text
            )
        }
        return line
    }

    /// Runs of columns with the same look joined where one ends at the next one's start.
    private static func merged<Run>(
        _ runs: [Run],
        columns: WritableKeyPath<Run, Range<Int>>,
        same: (Run, Run) -> Bool
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
