internal import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The picker's rows for this frame: none while an approval question waits, since the question has the keys.
    static func pickerLines(for state: ScreenState, columns: Int, rows: Int) -> [Line] {
        guard state.pendingApproval == nil, let picker = state.picker else { return [] }
        return pickerLines(picker, columns: columns, rows: rows)
    }

    /// The picker's rows, a title and then the matches in view, drawn in text only: the choice is bold and in colour, and nothing is
    /// filled or marked (ADR-0044, the prototype's decisions). Nothing when there are not two rows to spend on it.
    /// - Parameters:
    ///   - picker: what to list.
    ///   - columns: the width every row is cut to.
    ///   - rows: the most rows it may take.
    /// - Returns: the title row and the matches in view, or nothing when there is no room.
    static func pickerLines(_ picker: CompletionPicker, columns: Int, rows: Int) -> [Line] {
        guard columns > 0, rows >= 1 else { return [] }
        // Nothing to choose yet, because the files are still being listed: the title alone says so.
        if picker.matches.isEmpty {
            return [Line(text: title(for: picker, shown: 0, columns: columns), style: Style(dim: true))]
        }
        let range = window(of: picker, rows: rows)
        let shown = range.count
        guard shown >= 1 else { return [] }
        let start = range.lowerBound
        let matches = picker.matches[range]
        let labels = matches.filter { !$0.isHeading }.map(\.label)
        let labelWidth = Swift.min(24, labels.map { UnicodeWidth.displayWidth(of: $0) }.max() ?? 0)
        var lines = [Line(text: title(for: picker, shown: shown, columns: columns), style: Style(dim: true))]
        for (offset, row) in matches.enumerated() {
            if row.isHeading {
                lines.append(Line(text: clipped(row.detail, to: columns), style: Style(dim: true)))
                continue
            }
            let label = row.label
            let padding = String(
                repeating: " ", count: Swift.max(0, labelWidth - UnicodeWidth.displayWidth(of: label)) + 2)
            let chosen = start + offset == picker.selected
            lines.append(
                Line(
                    text: clipped(row.detail.isEmpty ? label : label + padding + row.detail, to: columns),
                    style: chosen ? Style(fg: .indexed(6), bold: true) : .default))
        }
        return lines
    }

    /// The matches that are drawn in `rows` rows: the window the picker scrolls in, cut to leave a row for the title and to keep the
    /// choice in view. Empty when none are drawn. A click maps a row back to a match through this same range.
    static func window(of picker: CompletionPicker, rows: Int) -> Range<Int> {
        let shown = Swift.min(picker.visible.count, rows - 1)
        guard shown >= 1 else { return 0 ..< 0 }
        let start = Swift.min(Swift.max(picker.firstVisible, picker.selected - shown + 1), picker.selected)
        return start ..< Swift.min(picker.matches.count, start + shown)
    }

    /// What the list is, how far down it the choice is when it does not all fit, and the keys, as many as the width has room for.
    private static func title(for picker: CompletionPicker, shown: Int, columns: Int) -> String {
        let name = picker.kind.title
        let choiceNumber = picker.choiceIndexes.firstIndex(of: picker.selected).map { $0 + 1 }
        let position =
            picker.countOfChoices > shown && shown > 0
            ? " \(choiceNumber ?? 1) of \(picker.countOfChoices)" : ""
        let heading = name + position + (picker.caption.isEmpty ? "" : " · " + picker.caption)
        let chooses: Bool = if case .choices = picker.kind { true } else { false }
        let config: Bool = if case .config = picker.kind { true } else { false }
        let options =
            picker.matches.isEmpty
            ? [heading, name]
            : chooses
                ? [
                    heading + " · ↑↓ then Enter chooses · Esc closes", heading + " · Enter chooses · Esc closes",
                    heading, name
                ]
                : config
                    ? [
                        heading + " · ↑↓ move · ←→ change · Enter saves · Esc closes",
                        heading + " · ←→ change · Enter saves · Esc closes", heading, name
                    ]
                    : [
                        heading + " · Enter or Tab inserts · Esc closes", heading + " · Enter inserts · Esc closes",
                        heading,
                        name + position, name
                    ]
        return clipped(options.first { UnicodeWidth.displayWidth(of: $0) <= columns } ?? name, to: columns)
    }

    /// `text` cut to `columns` cells at a grapheme boundary, never wider.
    private static func clipped(_ text: String, to columns: Int) -> String {
        guard UnicodeWidth.displayWidth(of: text) > columns else { return text }
        return ColumnSlicer.split(text, columns: 0 ..< columns).selected
    }
}
