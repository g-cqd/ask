internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The model's questions above the input (roadmap 0117), spaced as the approval section is: for a series, a row of tabs with the
    /// one shown in brackets and the review last; the question in bold; a row per choice with its mark (`( )` for one choice, `[ ]` for
    /// several, filled when checked), its number, its words and, dimmed, what it means; the note row after the last choice; a line under
    /// it when Enter was held; a dim row of the keys. What has the focus is drawn in the accent colour. The review lists each question's
    /// header and answer instead. When rows are short, the rows above the choices go first.
    static func questionLines(_ pending: PendingQuestions, columns: Int, rows: Int) -> [Line] {
        questionLayout(pending, columns: columns, rows: rows).lines
    }

    /// The section's rows, which of them are the choices (or the review's answers), and the row of the tabs when it is shown, so a
    /// click can act (roadmap 0117).
    static func questionLayout(_ pending: PendingQuestions, columns: Int, rows: Int)
        -> (lines: [Line], choices: Range<Int>, tabs: Int?)
    {
        guard columns > 0, rows >= 1 else { return ([], 0 ..< 0, nil) }
        let margin = "  "
        let width = Swift.max(1, columns - margin.count)
        let blank = Line(text: "", style: .default)
        var top: [Line] = pending.isSeries ? [tabLine(pending, columns: columns), blank] : []
        var body: [Line]
        if pending.reviewing {
            body = pending.questions.indices.map { index in
                Line(text: clipped(margin + review(pending, index), to: columns), style: .default)
            }
        } else {
            let question = pending.questions[pending.current]
            top += TextWrap.rows(question.question, width: width)
                .map { Line(text: margin + $0.text, style: Style(bold: true)) }
            if let problem = pending.problem {
                top.append(Line(text: clipped(margin + problem, to: columns), style: Style(fg: .indexed(1))))
            }
            top.append(blank)
            body = choiceLines(pending, columns: columns) + noteLines(pending, columns: columns)
        }
        let hint = Line(text: clipped(margin + keys(pending), to: columns), style: Style(dim: true))
        let choiceCount = body.count
        body += [blank, hint]
        guard body.count < rows else { return (Array(body.prefix(rows)), 0 ..< Swift.min(rows, choiceCount), nil) }
        let kept = Array(top.suffix(rows - body.count))
        let tabs = pending.isSeries && kept.count == top.count ? 0 : nil
        return (kept + body, kept.count ..< kept.count + choiceCount, tabs)
    }

    /// The columns of each tab on the tab row, in order, the review last.
    static func questionTabColumns(_ pending: PendingQuestions) -> [Range<Int>] {
        var column = 2  // the margin
        var spans: [Range<Int>] = []
        for name in tabNames(pending) {
            let width = UnicodeWidth.displayWidth(of: name) + 2
            spans.append(column ..< column + width)
            column += width + 2
        }
        return spans
    }

    private static func tabNames(_ pending: PendingQuestions) -> [String] {
        pending.questions.map(\.header) + ["✓ Review"]
    }

    /// `[Scope]   Tests    ✓ Review`: the question shown, or the review, in brackets, in the accent colour while the tabs have the focus.
    /// No numbers: beside the question count they read as one (owner, 2026-10-31).
    private static func tabLine(_ pending: PendingQuestions, columns: Int) -> Line {
        let names = tabNames(pending)
        let shown = pending.reviewing ? names.count - 1 : pending.current
        let text = names.enumerated().map { $0.offset == shown ? "[\($0.element)]" : " \($0.element) " }
            .joined(separator: "  ")
        var line = Line(text: clipped("  " + text, to: columns), style: .default)
        if pending.focus == .tabs, !pending.reviewing, questionTabColumns(pending).indices.contains(shown) {
            let span = questionTabColumns(pending)[shown]
            let end = Swift.min(span.upperBound, UnicodeWidth.displayWidth(of: line.text))
            if span.lowerBound < end {
                line.accents = [Accent(columns: span.lowerBound ..< end, style: Style(fg: .indexed(5), bold: true))]
            }
        }
        return line
    }

    /// One row per choice: cursor, mark, number, words, and what it means. The highlighted choice is marked only while the choices have
    /// the focus.
    private static func choiceLines(_ pending: PendingQuestions, columns: Int) -> [Line] {
        let question = pending.questions[pending.current]
        let cursor = pending.focus == .choices ? pending.cursors[pending.current] : -1
        let widest = question.choices.map { UnicodeWidth.displayWidth(of: $0.label) }.max() ?? 0
        return question.choices.enumerated()
            .map { index, choice in
                let checked = pending.chosen[pending.current].contains(index)
                let box = question.multiple ? (checked ? "[✓]" : "[ ]") : (checked ? "(•)" : "( )")
                let lead = index == cursor ? "›" : " "
                let start = "  \(lead)  \(box)  \(index + 1)   \(choice.label)"
                let gap = String(repeating: " ", count: widest - UnicodeWidth.displayWidth(of: choice.label))
                var line = Line(
                    text: clipped(start + (choice.detail.map { gap + "   " + $0 } ?? ""), to: columns),
                    style: index == cursor ? Style(fg: .indexed(5), bold: true) : .default)
                if choice.detail != nil {
                    let from = Swift.min(
                        UnicodeWidth.displayWidth(of: start + gap), UnicodeWidth.displayWidth(of: line.text))
                    line.accents = [
                        Accent(columns: from ..< UnicodeWidth.displayWidth(of: line.text), style: Style(dim: true))
                    ]
                }
                return line
            }
    }

    /// `Scope: Only the parser; note: keep the API`.
    private static func review(_ pending: PendingQuestions, _ index: Int) -> String {
        let question = pending.questions[index]
        let answer = pending.answers[index]
        let labels = answer.chosen.compactMap {
            question.choices.indices.contains($0) ? question.choices[$0].label : nil
        }
        var parts =
            // @dl:accept -- the review says an answer as the tool's result does, in the screen's module, which cannot see AskTools
            labels.isEmpty ? (question.choices.isEmpty ? [] : ["nothing chosen"]) : [labels.joined(separator: ", ")]
        if !answer.note.isEmpty { parts.append("note: \(answer.note)") }
        return "\(question.header): " + (parts.isEmpty ? "no answer" : parts.joined(separator: "; "))
    }

    /// The keys that act now, for what has the focus.
    private static func keys(_ pending: PendingQuestions) -> String {
        if pending.reviewing { return "Enter sends these answers · Esc goes back" }
        let question = pending.questions[pending.current]
        let last = pending.current == pending.questions.count - 1
        let enter = last ? (pending.isSeries ? "Enter reviews" : "Enter answers") : "Enter next"
        var parts: [String]
        switch pending.focus {
            case .tabs: parts = ["← → change question"]
            case .choices: parts = ["↑ ↓ highlight", question.multiple ? "Space checks several" : "Space selects"]
            case .note: parts = [question.note == .required ? "type the note (needed)" : "type a note"]
        }
        if pending.focusOrder.count > 1 { parts.append("Tab moves") }
        return (parts + [enter, "Esc declines"]).joined(separator: " · ")
    }
}
