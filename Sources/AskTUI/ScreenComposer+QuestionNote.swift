internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// Where the note's label starts: under the choices' marks.
    static let questionNoteIndent = 5

    /// The note row of the question shown, after its last choice (owner, 2026-10-31): `Note` under the choices' marks, then what is
    /// typed, wrapped at the screen's width with every row after the first indented to the text. Focused, it is drawn in the accent
    /// colour with its cursor as an inverse cell; empty and not focused, a dim word says whether a note is wanted. None for a question
    /// that takes no note.
    static func noteLines(_ pending: PendingQuestions, columns: Int) -> [Line] {
        let question = pending.questions[pending.current]
        guard question.note != .none else { return [] }
        let label = String(repeating: " ", count: questionNoteIndent) + "Note  "
        let indent = UnicodeWidth.displayWidth(of: label)
        let width = Swift.max(1, columns - indent)
        let editor = pending.notes[pending.current]
        let focused = pending.focus == .note
        let labelStyle = focused ? Style(fg: .indexed(5), bold: true) : Style(dim: true)
        guard !editor.text.isEmpty || focused else {
            let placeholder =
                question.note == .required ? "needed: Tab here and type it" : "optional: Tab here and type it"
            return [noteRow(label, placeholder, columns: columns, label: labelStyle, text: Style(dim: true))]
        }
        // An empty note still has its row, for the cursor: a space wraps to one empty row at offset zero.
        let shown =
            editor.text.isEmpty
            ? TextWrap.rows(" ", width: width)
                .map { row in
                    var row = row
                    row.text = ""
                    return row
                } : TextWrap.rows(editor.text, width: width)
        var lines = shown.enumerated()
            .map { index, row in
                noteRow(
                    index == 0 ? label : String(repeating: " ", count: indent), row.text, columns: columns,
                    label: labelStyle, text: .default)
            }
        if focused, let (row, column) = noteCursor(editor, rows: shown) {
            let at = indent + column
            if at >= UnicodeWidth.displayWidth(of: lines[row].text) {
                lines[row].text += String(
                    repeating: " ", count: at + 1 - UnicodeWidth.displayWidth(of: lines[row].text))
            }
            lines[row].accents.append(Accent(columns: at ..< at + 1, style: Style(inverse: true)))
        }
        return lines
    }

    /// One row of the note: its lead (the label or the indent) styled as the label, then the text.
    private static func noteRow(_ lead: String, _ text: String, columns: Int, label: Style, text style: Style) -> Line {
        var line = Line(text: clipped(lead + text, to: columns), style: style)
        let leadWidth = Swift.min(UnicodeWidth.displayWidth(of: lead), UnicodeWidth.displayWidth(of: line.text))
        if leadWidth > 0 { line.accents = [Accent(columns: 0 ..< leadWidth, style: label)] }
        return line
    }

    /// The wrapped row and the column within it of the editor's cursor.
    private static func noteCursor(_ editor: PromptEditor, rows: [TextWrap.Row]) -> (Int, Int)? {
        let before = editor.text.prefix(editor.cursor)
        let line = before.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        let column = before.split(separator: "\n", omittingEmptySubsequences: false).last.map(\.count) ?? 0
        guard let index = rows.lastIndex(where: { $0.line == line && $0.offset <= column }) else { return nil }
        let row = rows[index]
        let within = Swift.min(Swift.max(0, column - row.offset), row.text.count)
        return (index, UnicodeWidth.displayWidth(of: String(row.text.prefix(within))))
    }
}
