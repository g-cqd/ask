internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The section's left margin.
    private static let approvalMargin = "  "

    /// The approval section above the input (roadmaps 0116, 0157), spaced to be read at a glance: a margin, the question wrapped in
    /// bold, the call's command (one row until unfolded, then every line) and a blank row after it, then a row per answer with its
    /// checkbox drawn in strokes (`[✓]` checked, `[ ]` not; brackets stop short of the cell's top and bottom, so boxes on rows above
    /// each other never touch), its number, its words, and its letter in a column of their own, and a blank row before the input. The
    /// row the arrows are on is marked `›`, bold and in colour. When rows are short the blank rows go first, then the rows above the
    /// answers from the bottom; the answers are kept.
    static func approvalLines(_ pending: PendingApproval, columns: Int, rows: Int) -> [Line] {
        approvalLayout(pending, columns: columns, rows: rows).lines
    }

    /// The section's rows, which of them are the answers, and which the command, so a click on one can act.
    static func approvalLayout(_ pending: PendingApproval, columns: Int, rows: Int)
        -> (lines: [Line], answers: Range<Int>, detail: Range<Int>)
    {
        guard columns > 0, rows >= 1 else { return ([], 0 ..< 0, 0 ..< 0) }
        let margin = approvalMargin
        let width = Swift.max(1, columns - margin.count)
        let question = TextWrap.rows(pending.question, width: width)
            .map { Line(text: margin + $0.text, style: Style(bold: true)) }
        let detail = pending.detail.map { approvalDetailLines($0, open: pending.showsWholeDetail, width: width) } ?? []
        let answers = approvalAnswerLines(pending, columns: columns)
        let blank = Line(text: "", style: .default)
        let spare = rows - answers.count
        guard spare > 0 else { return (Array(answers.prefix(rows)), 0 ..< Swift.min(rows, answers.count), 0 ..< 0) }
        let top = question + detail
        let separated = spare >= 2
        let tail = spare >= top.count + 2
        let kept = Array(top.prefix(spare - (separated ? 1 : 0) - (tail ? 1 : 0)))
        let above = kept + (separated ? [blank] : [])
        let detailRows = Swift.min(question.count, kept.count) ..< kept.count
        return (above + answers + (tail ? [blank] : []), above.count ..< above.count + answers.count, detailRows)
    }

    /// The command: its first line, cut to fit, with how much more there is and the key that shows it; or every line, wrapped.
    private static func approvalDetailLines(_ detail: String, open: Bool, width: Int) -> [Line] {
        let margin = approvalMargin
        if open { return TextWrap.rows(detail, width: width).map { Line(text: margin + $0.text, style: .default) } }
        let lines = detail.split(separator: "\n", omittingEmptySubsequences: false)
        let first = String(lines.first ?? "")
        let more = lines.count - 1
        let fits = UnicodeWidth.displayWidth(of: first) <= width
        guard more > 0 || !fits else { return [Line(text: margin + first, style: .default)] }
        let hint = more > 0 ? "  (+\(more) line\(more == 1 ? "" : "s") · Ctrl+O)" : "  (Ctrl+O)"
        let room = Swift.max(1, width - UnicodeWidth.displayWidth(of: hint) - 1)
        let shown = fits && UnicodeWidth.displayWidth(of: first) <= room ? first : clipped(first, to: room) + "…"
        var line = Line(text: margin + shown + hint, style: .default)
        let start = UnicodeWidth.displayWidth(of: margin + shown)
        line.accents = [Accent(columns: start ..< start + UnicodeWidth.displayWidth(of: hint), style: Style(dim: true))]
        return [line]
    }

    /// One row per answer: cursor, checkbox, number, words, letter.
    private static func approvalAnswerLines(_ pending: PendingApproval, columns: Int) -> [Line] {
        let widest = pending.options.map { UnicodeWidth.displayWidth(of: $0.label) }.max() ?? 0
        return pending.options.enumerated()
            .map { index, option in
                let box = index == pending.checked ? "[✓]" : "[ ]"
                let lead = index == pending.cursor ? "›" : " "
                let gap = String(repeating: " ", count: widest - UnicodeWidth.displayWidth(of: option.label))
                let text = "\(approvalMargin)\(lead)  \(box)  \(index + 1)   \(option.label)\(gap)   \(option.letter)"
                let style = index == pending.cursor ? Style(fg: .indexed(5), bold: true) : Style.default
                return Line(text: clipped(text, to: columns), style: style)
            }
    }
}
