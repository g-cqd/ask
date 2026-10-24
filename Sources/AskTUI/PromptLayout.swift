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
    }

    private var cache: (text: String, columns: Int, layout: InputLayout)?
    private var firstRow = 0

    /// Clip the ASCII prefix on tiny terminals, always leaving a cell for text or the cursor.
    static func prefix(columns: Int) -> String {
        String(ScreenComposer.prompt.prefix(max(1, columns) - 1))
    }

    mutating func frame(_ editor: PromptEditor, columns: Int, screenRows: Int, maximumRows: Int) -> Frame {
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
        return Frame(lines: lines, cursor: viewport.cursor, indicator: indicator, top: firstRow, layout: layout)
    }
}
