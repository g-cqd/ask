internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The section's left margin.
    private static let approvalMargin = "  "

    /// The approval section above the input (roadmap 0116), spaced to be read at a glance: a margin, the question wrapped in bold, a blank
    /// row, then a row per answer with its checkbox drawn in strokes (`[✓]` checked, `[ ]` not; brackets stop short of the cell's top and
    /// bottom, so boxes on rows above each other never touch), its number, its words, and its letter in a column of their own, and a blank row before the input. The row
    /// the arrows are on is marked `›`, bold and in colour. When rows are short the blank rows go first, then the question's rows; the
    /// answers are kept.
    static func approvalLines(_ pending: PendingApproval, columns: Int, rows: Int) -> [Line] {
        guard columns > 0, rows >= 1 else { return [] }
        let margin = approvalMargin
        let question = TextWrap.rows(pending.question, width: Swift.max(1, columns - margin.count))
            .map { Line(text: margin + $0.text, style: Style(bold: true)) }
        let widest = pending.options.map { UnicodeWidth.displayWidth(of: $0.label) }.max() ?? 0
        let answers = pending.options.enumerated()
            .map { index, option in
                let box = index == pending.checked ? "[✓]" : "[ ]"
                let lead = index == pending.cursor ? "›" : " "
                let gap = String(repeating: " ", count: widest - UnicodeWidth.displayWidth(of: option.label))
                let text = "\(margin)\(lead)  \(box)  \(index + 1)   \(option.label)\(gap)   \(option.letter)"
                let style = index == pending.cursor ? Style(fg: .indexed(5), bold: true) : Style.default
                return Line(text: clipped(text, to: columns), style: style)
            }
        let spare = rows - answers.count
        guard spare > 0 else { return Array(answers.prefix(rows)) }
        guard spare > 1 else { return [question[0]] + answers }
        let blank = Line(text: "", style: .default)
        guard spare > 2 else { return question.prefix(spare - 1) + [blank] + answers }
        return question.prefix(spare - 2) + [blank] + answers + [blank]
    }
}
