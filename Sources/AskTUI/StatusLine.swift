internal import TerminalKitStyle
internal import TerminalKitText

/// The status line as pieces fitted to the width: a piece is shown whole, in a shorter form, or not at all, and never cut in the middle
/// (roadmap 0074). What does not fit goes in order of priority, lowest first; the model's name goes last, and only then is it clipped.
struct StatusLine {
    /// The separator between pieces.
    static let separator = " · "
    /// The colour of a warning mark at the start of the label.
    static let warning = Style(fg: .indexed(3))

    private(set) var segments: [StatusSegment]
    let columns: Int
    var markStyle: Style?

    /// The default look of the status line text and enclosing input rules.
    static let statusStyle = Style(dim: true)

    /// Fits `segments`, in the order they are to be shown, to `columns`.
    init(_ segments: [StatusSegment], columns: Int, markStyle: Style? = nil) {
        self.segments = segments
        self.columns = Swift.max(1, columns)
        self.markStyle = markStyle
        fit()
    }

    private var width: Int {
        segments.reduce(0) { $0 + UnicodeWidth.displayWidth(of: $1.text) }
            + Swift.max(0, segments.count - 1) * UnicodeWidth.displayWidth(of: Self.separator)
    }

    /// Shortens the least important piece that can be shortened, else drops the least important that may be, until the line fits.
    private mutating func fit() {
        while width > columns {
            guard let index = segments.indices.min(by: { segments[$0].priority < segments[$1].priority }) else {
                return
            }
            // The least important piece is shortened or dropped before a more important one is touched.
            if segments[index].hasShorterForm {
                segments[index].form += 1
            } else if segments[index].droppable, segments.count > 1 {
                segments.remove(at: index)
            } else if let other = segments.indices.filter({ segments[$0].hasShorterForm })
                .min(by: {
                    segments[$0].priority < segments[$1].priority
                })
            {
                segments[other].form += 1
            } else {
                return
            }
        }
    }

    /// The row, with the columns the clickable pieces cover and an accent on the leading mark.
    func line(style: Style) -> (line: ScreenComposer.Line, runners: Range<Int>?, below: Range<Int>?) {
        var text = ""
        var column = 0
        var runners: Range<Int>?
        var below: Range<Int>?
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                text += Self.separator
                column += UnicodeWidth.displayWidth(of: Self.separator)
            }
            let span = column ..< column + UnicodeWidth.displayWidth(of: segment.text)
            switch segment.target {
                case .runners: runners = span
                case .below: below = span
                case .none: break
            }
            text += segment.text
            column = span.upperBound
        }
        var accents: [ScreenComposer.Accent] = []
        if let markStyle, let first = text.first {
            accents = [.init(columns: 0 ..< UnicodeWidth.displayWidth(of: String(first)), style: markStyle)]
        } else if let first = text.first, first == "!" || first == "⚠" {
            accents = [.init(columns: 0 ..< UnicodeWidth.displayWidth(of: String(first)), style: Self.warning)]
        }
        // Only when even the pieces that may not go do not fit: clipped at a cell, the last resort.
        if UnicodeWidth.displayWidth(of: text) > columns {
            text = ColumnSlicer.split(text, columns: 0 ..< columns).selected
        }
        return (ScreenComposer.Line(text: text, style: style, accents: accents), runners, below)
    }
}
