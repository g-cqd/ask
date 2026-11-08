internal import TerminalKitStyle
internal import TerminalKitText

/// The box around the input (note n36, the owner's choices of 2026-11-08): rounded corners, a border down each side with a column of space
/// inside it, in the session's colour where `ui.sessionTint` puts it there, else the grey of secondary text.
struct InputBox {
    /// Its columns, borders included: the input's width and four more.
    var width: Int
    var style: Style

    var top: ScreenComposer.Line { edge("╭", "╮") }
    var bottom: ScreenComposer.Line { edge("╰", "╯") }

    private func edge(_ left: String, _ right: String) -> ScreenComposer.Line {
        ScreenComposer.Line(text: left + String(repeating: "─", count: Swift.max(0, width - 2)) + right, style: style)
    }

    /// `line`, one of the input's rows, inside the borders: its text two columns in and padded to the right border, its accents and
    /// highlight moved with it.
    func enclosing(_ line: ScreenComposer.Line, highlight: Range<Int>?) -> (ScreenComposer.Line, Range<Int>?) {
        let inner = width - 4
        let padding = String(repeating: " ", count: Swift.max(0, inner - UnicodeWidth.displayWidth(of: line.text)))
        var boxed = line
        boxed.text = "│ " + line.text + padding + " │"
        boxed.accents =
            [ScreenComposer.Accent(columns: 0 ..< 1, style: style)]
            + line.accents.map {
                ScreenComposer.Accent(columns: $0.columns.lowerBound + 2 ..< $0.columns.upperBound + 2, style: $0.style)
            }
            + [ScreenComposer.Accent(columns: width - 1 ..< width, style: style)]
        return (boxed, highlight.map { $0.lowerBound + 2 ..< $0.upperBound + 2 })
    }
}
