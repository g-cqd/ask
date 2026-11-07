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
        besideTranscript: Bool = true,
        into buffer: inout ScreenBuffer
    ) -> (sidebar: Sidebar, map: RowMap<Int>, totalLines: Int) {
        followLane(state.lane?.id)
        // In the bottom band the sidebar is drawn with the input, and the transcript keeps the whole width.
        let sidebar = besideTranscript ? Sidebar(state, columns: columns, rows: transcriptRows) : Sidebar()
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
        // The hovered block's header (roadmap 0172): every row of its hard line 0 on screen, so a wrapped one lights whole and the
        // padding row above it is not taken for it (note n13).
        let hovered: Int? = if case .block(let block) = state.hover { block } else { nil }
        for row in 0 ..< transcriptRows {
            let index = row - (transcriptRows - visible.count)
            var line = index >= 0 ? visible[visible.startIndex + index] : Line(text: "", style: .default)
            if let hovered, line.source?.block == hovered, line.source?.line == 0 { line = Self.brightened(line) }
            write(
                line,
                highlight: highlights[row],
                side: sidebar.cells.indices.contains(row) ? sidebar.cells[row] : nil,
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
        if used < edge {
            // The rest of the row carries the row's own background, so a tinted block is tinted to its edge: the screen's, or the
            // sidebar's divider, never into the sidebar.
            buffer.fill(
                row: row,
                col: used,
                width: edge - used,
                height: 1,
                cell: Cell(character: " ", style: Style(bg: line.style.bg), width: 1)
            )
        }
        if let side {
            // The panel is the page's own: blanked first, whatever the transcript row under it was tinted. The closed panel's corner
            // keeps the row's own background, so a tinted block is not notched.
            let background = side.divider ? Style() : Style(bg: line.style.bg)
            buffer.fill(
                row: row,
                col: side.column,
                width: buffer.columns - side.column,
                height: 1,
                cell: Cell(character: " ", style: background, width: 1)
            )
            // In the page's grey once the terminal said its colours, as the transcript's faint rows are: faint is unreadable on some.
            let divider = Style(dim: true)
            if side.divider { buffer.write("│", row: row, col: side.column, style: theme?.legible(divider) ?? divider) }
            var style = side.style
            if !side.divider { style.bg = line.style.bg }
            buffer.write(
                side.text,
                row: row,
                col: side.column + (side.divider ? 1 : 0),
                style: theme?.legible(style) ?? style
            )
        }
    }
}
