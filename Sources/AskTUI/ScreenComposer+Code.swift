internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The rows item `index` draws as, folds applied: what the screen shows, and what a fold toggle measures before and after.
    static func lines(in transcript: Transcript, at index: Int, columns: Int) -> [Line] {
        lines(in: transcript, at: index, shown: transcript.shownCode(at: index), columns: columns)
    }

    /// The same, for a caller that has already worked out what an assistant message shows.
    static func lines(in transcript: Transcript, at index: Int, shown: ShownCode?, columns: Int) -> [Line] {
        guard let shown else {
            return lines(
                for: transcript.items[index], folded: transcript.isFolded(index), block: index, columns: columns)
        }
        // A placeholder is dim, like the other folds' headers; the rest of the message, open code included, is as it was.
        return TextWrap.rows(shown.text, width: columns)
            .map { row in
                Line(
                    text: row.text, style: shown.placeholders.contains(row.line) ? Style(dim: true) : .default,
                    source: Source(block: index, line: row.line, offset: row.offset, col: 0, text: row.text))
            }
    }
}
