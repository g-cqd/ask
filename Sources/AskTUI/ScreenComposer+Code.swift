internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The rows item `index` draws as, folds applied: what the screen shows, and what a fold toggle measures before and after.
    static func lines(in transcript: Transcript, at index: Int, columns: Int, style: BlockStyle = .plain) -> [Line] {
        lines(in: transcript, at: index, shown: transcript.shownCode(at: index), columns: columns, style: style)
    }

    /// The same, for a caller that has already worked out what an assistant message shows.
    static func lines(
        in transcript: Transcript, at index: Int, shown: ShownCode?, columns: Int, style: BlockStyle = .plain
    ) -> [Line] {
        let item = transcript.items[index]
        let spaced = index > 0 && isSpaced(item) && isSpaced(transcript.items[index - 1])
        guard let shown else {
            return lines(
                for: item, folded: transcript.isFolded(index), block: index, columns: columns, style: style,
                spacerAbove: spaced, progress: transcript.progress[index],
                toolInput: transcript.shownToolInput(at: index))
        }
        // A placeholder is dim, like the other folds' headers; the rest of the message, open code included, is as it was.
        let margin = String(repeating: " ", count: style.inset)
        let content = TextWrap.rows(shown.text, width: Swift.max(1, columns - 2 * style.inset))
            .map { row in
                Line(
                    text: margin + row.text, style: shown.placeholders.contains(row.line) ? Style(dim: true) : .default,
                    source: Source(block: index, line: row.line, offset: row.offset, col: style.inset, text: row.text))
            }
        return framed(content, kind: item, style: style, spacerAbove: spaced)
    }
}
