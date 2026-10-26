internal import TerminalKitText

/// Keeping the transcript's wrapped lines current, and mapping a screen row back to the conversation.
extension ScreenComposer {
    /// Which content each transcript row shows, for mapping a cell back to the conversation.
    static func provenance(of visible: ArraySlice<Line>, rows: Int, transcriptRows: Int) -> RowMap<Int> {
        var map = RowMap<Int>()
        map.reset(rowCount: rows)
        for row in 0 ..< transcriptRows {
            let index = row - (transcriptRows - visible.count)
            guard index >= 0, let source = visible[visible.startIndex + index].source else { continue }
            map.set(
                row: row,
                to: RowProvenance(
                    block: source.block, ordinal: source.block, line: source.line, firstOffset: source.offset,
                    col: source.col, text: source.text))
        }
        return map
    }

    mutating func updateTranscriptLines(_ transcript: Transcript, columns: Int, style: BlockStyle = .plain) {
        // A different look lays every block out again.
        if style != blockStyle {
            blockStyle = style
            transcriptLines = LayoutCache<Line>()
        }
        var hard = hardLines
        transcriptLines.update(width: columns, revisions: transcript.revisions) { index in
            if hard.count <= index { hard.append(contentsOf: repeatElement([], count: index + 1 - hard.count)) }
            // Found once per layout: the hard lines a selection reads and the rows drawn come from the same folds.
            let shown = transcript.shownCode(at: index)
            hard[index] = TranscriptContent.hardLines(of: shown?.text ?? transcript.contentText(at: index))
            return Self.lines(in: transcript, at: index, shown: shown, columns: columns, style: style)
        }
        hard.removeLast(Swift.max(0, hard.count - transcript.items.count))
        hardLines = hard
    }
}
