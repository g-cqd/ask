internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

// Writing the transcript's rows into the buffer; apart from ScreenComposer.swift to keep each file under
// the 250-line ceiling and the type body under 200 lines.
extension ScreenComposer {
    /// Draws the transcript's visible rows, ``transcriptRows`` of them, with the sidebar beside them, and says what each row
    /// shows.
    mutating func writeTranscript(
        _ state: ScreenState,
        rows: Int,
        columns: Int,
        into buffer: inout ScreenBuffer
    ) -> (sidebar: Sidebar, map: RowMap<Int>, totalLines: Int) {
        let sidebar = Sidebar(state, columns: columns, rows: transcriptRows)
        let wrapColumns = sidebar.transcriptColumns(of: columns)
        let visible = transcriptWindow(
            state.transcript,
            columns: wrapColumns,
            style: state.blocks,
            rows: transcriptRows,
            rowsFromEnd: state.scrollback
        )[...]
        let map = Self.provenance(of: visible, rows: rows, transcriptRows: transcriptRows)
        foldBlocks = Array(repeating: nil, count: transcriptRows - visible.count) + visible.map(\.foldBlock)
        middleFolds = Array(repeating: false, count: transcriptRows - visible.count) + visible.map(\.foldsMiddle)
        rowLinks = Array(repeating: [], count: transcriptRows - visible.count) + visible.map(\.links)
        var highlights = [Range<Int>?](repeating: nil, count: transcriptRows)
        if let selection = state.selection {
            for span in map.highlights(of: selection, in: ShownTranscriptContent(transcript: state.transcript))
            where span.row < transcriptRows {
                // A row of Markdown can have a span per stretch it shows; the row paints them as one.
                let earlier = highlights[span.row]
                highlights[span.row] =
                    Swift.min(earlier?.lowerBound ?? span.startCol, span.startCol)
                    ..< Swift.max(earlier?.upperBound ?? span.endCol, span.endCol)
            }
        }
        for row in 0 ..< transcriptRows {
            let index = row - (transcriptRows - visible.count)
            let line = index >= 0 ? visible[visible.startIndex + index] : Line(text: "", style: .default)
            write(
                line,
                highlight: highlights[row],
                side: sidebar.cells.isEmpty ? nil : sidebar.cells[row],
                row: row,
                into: &buffer
            )
        }
        return (sidebar, map, transcriptLines.rowCount)
    }

    /// Writes a whole row, the text then blanks to the edge, unless the row already holds exactly this.
    mutating func write(
        _ line: Line,
        highlight: Range<Int>? = nil,
        side: Sidebar.Cell? = nil,
        row: Int,
        into buffer: inout ScreenBuffer
    ) {
        let now = Shown(
            text: line.text,
            style: line.style,
            accents: line.accents,
            links: line.links,
            highlight: highlight,
            side: side
        )
        guard shown[row] != now else { return }
        shown[row] = now
        var column = 0
        for (part, style) in Self.spans(of: line, highlight: highlight, row: row) {
            buffer.write(part, row: row, col: column, style: theme?.legible(style) ?? style)
            column += UnicodeWidth.displayWidth(of: part)
        }
        let edge = side?.column ?? buffer.columns
        let used = Swift.min(edge, UnicodeWidth.displayWidth(of: line.text))
        if used < buffer.columns {
            // The rest of the row carries the row's own background, so a tinted block is tinted to the edge.
            buffer.fill(
                row: row,
                col: used,
                width: buffer.columns - used,
                height: 1,
                cell: Cell(character: " ", style: Style(bg: line.style.bg), width: 1)
            )
        }
        if let side {
            buffer.write("│", row: row, col: side.column, style: Style(dim: true))
            buffer.write(side.text, row: row, col: side.column + 1, style: side.style)
        }
    }
}
