internal import TerminalKitText

/// ask's input policy over TerminalKit's display-row map: its prefix, row limit and clipping cue. The layout is reused while only the
/// cursor moves; the retained viewport top prevents unnecessary jumps inside a tall draft.
struct PromptLayout: Sendable {
    struct Frame: Sendable {
        var lines: [String]
        var cursor: InputLayout.Position
        var indicator: String
        /// The display row of the draft that is the first one drawn, and the whole map, so a click maps back to the text.
        var top: Int
        var layout: InputLayout
        /// The cells of each drawn row that are selected, or nil; empty when nothing is selected.
        var highlights: [Range<Int>?]
    }

    private var cache: (text: String, columns: Int, layout: InputLayout)?
    private var firstRow = 0

    /// Clip the ASCII prefix on tiny terminals, always leaving a cell for text or the cursor.
    static func prefix(columns: Int) -> String {
        String(ScreenComposer.prompt.prefix(max(1, columns) - 1))
    }

    mutating func frame(
        _ editor: PromptEditor, columns: Int, screenRows: Int, maximumRows: Int, selection: Range<Int>? = nil
    ) -> Frame {
        let prefix = Self.prefix(columns: columns)
        let layout: InputLayout
        if let cache, cache.columns == columns, cache.text == editor.text {
            layout = cache.layout
        } else {
            layout = InputLayout(editor.text, columns: columns, firstRowIndent: prefix.count)
            cache = (editor.text, columns, layout)
        }
        let cap = min(max(1, maximumRows), max(1, screenRows / 3), max(1, screenRows - 1))
        let viewport = InputViewport(layout: layout, cursorOffset: editor.cursor, maximumRows: cap, firstRow: firstRow)
        firstRow = viewport.visibleRows.lowerBound
        let lines = viewport.visibleRows.map { row in (row == 0 ? prefix : "") + layout.rows[row] }
        let indicator =
            viewport.rowsAbove > 0 || viewport.rowsBelow > 0
            ? "input \(firstRow + 1)–\(viewport.visibleRows.upperBound) of \(layout.rows.count)" : ""
        // Nothing selected is the common frame: no array is made for it.
        let highlights =
            selection == nil
            ? []
            : viewport.visibleRows.map { Self.highlight(row: $0, of: layout, prefix: prefix, selection: selection) }
        return Frame(
            lines: lines, cursor: viewport.cursor, indicator: indicator, top: firstRow, layout: layout,
            highlights: highlights)
    }

    /// The cells of display row `row` a selection of characters covers: from where it starts on that row, or the row's first cell, to
    /// where it ends, or the row's last. A line break and the space after the last character of a row are not selected.
    private static func highlight(row: Int, of layout: InputLayout, prefix: String, selection: Range<Int>?) -> Range<
        Int
    >? {
        guard let selection, !selection.isEmpty else { return nil }
        let start = layout.position(at: selection.lowerBound)
        let end = layout.position(at: selection.upperBound)
        guard row >= start.row, row <= end.row else { return nil }
        let first = row == 0 ? prefix.count : 0
        let width = first + UnicodeWidth.displayWidth(of: layout.rows[row])
        let low = row == start.row ? start.column : first
        let high = row == end.row ? end.column : width
        return high > low ? low ..< high : nil
    }
}
