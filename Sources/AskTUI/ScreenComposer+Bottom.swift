internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// Writes everything under the transcript: the picker, the one input (in its box, or tinted), the status line below it, then the
    /// runner strip.
    /// - Parameters:
    ///   - panel: the open runners list, if any.
    ///   - status: the status line, or nil on a screen with no room for one.
    ///   - picker: the command picker's rows, if open: above the box.
    ///   - editor: the prompt's rows and cursor.
    ///   - band: the sidebar's cells beside the input's rows, from its first, when it is in the bottom band; the input's rows are
    ///     padded to as many.
    ///   - box: the box around the input, or nil for none.
    ///   - inputStyle: the style the input's rows are drawn in: its tint, when it has one.
    ///   - row: the first row under the transcript.
    ///   - buffer: where the rows go.
    /// - Returns: where the cursor belongs, in the prompt.
    mutating func writeBottom(
        panel: [Line],
        status: Line?,
        picker: [Line],
        editor: PromptLayout.Frame,
        band: [Sidebar.Cell?] = [],
        box: InputBox? = nil,
        inputStyle: Style = .default,
        from row: Int,
        into buffer: inout ScreenBuffer
    ) -> (row: Int, column: Int) {
        var next = row
        for line in picker {
            write(line, row: next, into: &buffer)
            next += 1
        }
        if let box {
            write(box.top, row: next, into: &buffer)
            next += 1
        }
        for offset in 0 ..< Swift.max(editor.lines.count, band.count) {
            let text = offset < editor.lines.count ? editor.lines[offset] : ""
            // A mark keeps the input's tint behind it.
            let accents = (editor.accents.indices.contains(offset) ? editor.accents[offset] : [])
                .map { accent in
                    var accent = accent
                    accent.style.bg = inputStyle.bg
                    return accent
                }
            var line = Line(text: text, style: inputStyle, accents: accents)
            var highlight = editor.highlights.indices.contains(offset) ? editor.highlights[offset] : nil
            if let box { (line, highlight) = box.enclosing(line, highlight: highlight) }
            write(
                line,
                highlight: highlight,
                side: band.indices.contains(offset) ? band[offset] : nil,
                row: next + offset,
                into: &buffer
            )
        }
        var below = next + Swift.max(editor.lines.count, band.count)
        if let box {
            write(box.bottom, row: below, into: &buffer)
            below += 1
        }
        if let status {
            write(status, row: below, into: &buffer)
            below += 1
        }
        for (offset, line) in panel.enumerated() { write(line, row: below + offset, into: &buffer) }
        return (next + editor.cursor.row, editor.cursor.column + (box == nil ? 0 : 2))
    }
}
