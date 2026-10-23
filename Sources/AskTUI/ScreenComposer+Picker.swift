internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The picker's rows for this frame: none while an approval question waits, since the question has the keys.
    static func pickerLines(for state: ScreenState, columns: Int, rows: Int) -> [Line] {
        guard state.pendingApproval == nil, let picker = state.picker else { return [] }
        return pickerLines(picker, columns: columns, rows: rows)
    }

    /// Writes `lines` from `row` down.
    /// - Returns: the row after the last one, where the prompt begins.
    mutating func writePicker(_ lines: [Line], from row: Int, into buffer: inout ScreenBuffer) -> Int {
        for (offset, line) in lines.enumerated() { write(line, row: row + offset, into: &buffer) }
        return row + lines.count
    }

    /// The picker's rows, a title and then the matches in view, drawn in text only: the choice is bold and in colour, and nothing is
    /// filled or marked (ADR-0044, the prototype's decisions). Nothing when there are not two rows to spend on it.
    /// - Parameters:
    ///   - picker: what to list.
    ///   - columns: the width every row is cut to.
    ///   - rows: the most rows it may take.
    /// - Returns: the title row and the matches in view, or nothing when there is no room.
    static func pickerLines(_ picker: CompletionPicker, columns: Int, rows: Int) -> [Line] {
        let shown = Swift.min(picker.visible.count, rows - 1)
        guard columns > 0, shown >= 1 else { return [] }
        let start = Swift.min(Swift.max(picker.firstVisible, picker.selected - shown + 1), picker.selected)
        let window = picker.matches[start ..< Swift.min(picker.matches.count, start + shown)]
        let labels = window.map { "/" + $0.name }
        let labelWidth = Swift.min(24, labels.map { UnicodeWidth.displayWidth(of: $0) }.max() ?? 0)
        var lines = [Line(text: title(for: picker, shown: shown, columns: columns), style: Style(dim: true))]
        for (offset, command) in window.enumerated() {
            let label = labels[offset]
            let padding = String(
                repeating: " ", count: Swift.max(0, labelWidth - UnicodeWidth.displayWidth(of: label)) + 2)
            let chosen = start + offset == picker.selected
            lines.append(
                Line(
                    text: clipped(label + padding + command.summary, to: columns),
                    style: chosen ? Style(fg: .indexed(6), bold: true) : .default))
        }
        return lines
    }

    /// What the list is, how far down it the choice is when it does not all fit, and the keys, as many as the width has room for.
    private static func title(for picker: CompletionPicker, shown: Int, columns: Int) -> String {
        let position = picker.matches.count > shown ? " \(picker.selected + 1) of \(picker.matches.count)" : ""
        let options = [
            "commands\(position) · Enter or Tab inserts · Esc closes",
            "commands\(position) · Enter inserts · Esc closes",
            "commands\(position)", "commands"
        ]
        return clipped(options.first { UnicodeWidth.displayWidth(of: $0) <= columns } ?? "commands", to: columns)
    }

    /// `text` cut to `columns` cells at a grapheme boundary, never wider.
    private static func clipped(_ text: String, to columns: Int) -> String {
        guard UnicodeWidth.displayWidth(of: text) > columns else { return text }
        return ColumnSlicer.split(text, columns: 0 ..< columns).selected
    }
}
