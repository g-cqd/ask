internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// Writes everything under the transcript: status, picker, the one input, then the runner strip.
    /// - Parameters:
    ///   - panel: the open runners list, if any.
    ///   - status: the status line, or nil on a screen with no room for one.
    ///   - picker: the command picker's rows, if open.
    ///   - editor: the prompt's rows and cursor.
    ///   - row: the first row under the transcript.
    ///   - buffer: where the rows go.
    /// - Returns: where the cursor belongs, in the prompt.
    mutating func writeBottom(
        panel: [Line], status: Line?, picker: [Line], editor: PromptLayout.Frame, from row: Int,
        into buffer: inout ScreenBuffer
    ) -> (row: Int, column: Int) {
        var next = row
        if let status {
            write(status, row: next, into: &buffer)
            next += 1
        }
        for line in picker {
            write(line, row: next, into: &buffer)
            next += 1
        }
        for (offset, text) in editor.lines.enumerated() {
            write(
                Line(text: text, style: .default),
                highlight: editor.highlights.isEmpty ? nil : editor.highlights[offset], row: next + offset,
                into: &buffer)
        }
        for (offset, line) in panel.enumerated() {
            write(line, row: next + editor.lines.count + offset, into: &buffer)
        }
        return (next + editor.cursor.row, editor.cursor.column)
    }
}
