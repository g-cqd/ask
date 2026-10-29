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
            let segments = visible[visible.startIndex + index].segments
            guard segments.isEmpty else {
                map.set(row: row, to: RowProvenance(block: source.block, ordinal: source.block, segments: segments))
                continue
            }
            map.set(
                row: row,
                to: RowProvenance(
                    block: source.block, ordinal: source.block, line: source.line, firstOffset: source.offset,
                    col: source.col, text: source.text))
        }
        return map
    }

    /// The transcript's rows from `rowsFromEnd` up to `rows` above it, laid out from the end as far as the window and a margin need
    /// (TerminalKit roadmap 0023): a long conversation is not laid out whole to open, to take a new width, or to be held.
    mutating func transcriptWindow(
        _ transcript: Transcript, columns: Int, style: BlockStyle, rows: Int, rowsFromEnd: Int
    ) -> [Line] {
        // A different look lays every block out again.
        if style != blockStyle {
            blockStyle = style
            transcriptLines = WindowedLayout<Line>()
        }
        let layout = { (index: Int) in
            Self.lines(
                in: transcript, at: index, shown: transcript.shownCode(at: index), columns: columns, style: style)
        }
        // A window above the shown rows is known too, so a scroll up by a page always has rows to go to.
        transcriptLines.update(
            width: columns, revisions: transcript.revisions, keepingFromEnd: rowsFromEnd + 2 * rows, layout: layout)
        return transcriptLines.lines(fromEnd: rowsFromEnd, rows: rows, layout: layout)
    }
}
