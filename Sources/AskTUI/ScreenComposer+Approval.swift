internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The approval section above the input (roadmap 0116): the question, wrapped, then one row per answer with a checkbox drawn in block
    /// characters (`▐█▌` checked, `▐ ▌` not), its number, its words and its letter; the row the arrows are on is bold and in colour.
    static func approvalLines(_ pending: PendingApproval, columns: Int, rows: Int) -> [Line] {
        guard columns > 0, rows >= 1 else { return [] }
        let question = TextWrap.rows(pending.question, width: columns)
            .map { Line(text: $0.text, style: Style(bold: true)) }
        let answers = pending.options.enumerated()
            .map { index, option in
                let box = index == pending.checked ? "▐█▌" : "▐ ▌"
                let lead = index == pending.cursor ? "› " : "  "
                let text = "\(lead)\(box) \(index + 1)  \(option.label)  · \(option.letter)"
                let style = index == pending.cursor ? Style(fg: .indexed(5), bold: true) : Style.default
                return Line(text: clipped(text, to: columns), style: style)
            }
        // The answers come first when rows are short: the question can be read in the lane's status line, the answers nowhere else.
        let kept = Swift.max(0, rows - answers.count)
        return Array(question.prefix(Swift.max(kept, rows > answers.count ? 1 : 0)) + answers.prefix(rows))
    }
}
