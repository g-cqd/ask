import TerminalKitStyle
import Testing

@testable import AskTUI

/// What the question section draws besides its tabs (roadmap 0117; the mutation run of 2026-11-08 found these unread): the tab under the
/// focus in the accent colour, the highlighted choice's cursor and colour, a choice's meaning dimmed, the review's sentences, and the
/// keys that act now.
@Suite("The question section's rows say what has the focus and what each key does")
struct QuestionRowsTests {
    private static let accent = Style(fg: .indexed(5), bold: true)

    private func series(focus: PendingQuestions.Focus = .choices, current: Int = 0) -> PendingQuestions {
        var pending = PendingQuestions(
            id: 1,
            questions: [
                ScreenQuestion(
                    question: "Which scope?",
                    header: "Scope",
                    choices: [.init(label: "Parser", detail: "only the parser"), .init(label: "All")],
                    note: .none
                ),
                ScreenQuestion(question: "Tests?", header: "Tests", choices: [.init(label: "Yes")], multiple: true)
            ]
        )
        pending.focus = focus
        pending.current = current
        return pending
    }

    private func layout(_ pending: PendingQuestions, rows: Int = 30) -> (lines: [ScreenComposer.Line], tabs: Int?) {
        let laid = ScreenComposer.questionLayout(pending, columns: 120, rows: rows)
        return (laid.lines, laid.tabs)
    }

    private func hint(_ pending: PendingQuestions) -> String {
        layout(pending).lines.last?.text ?? ""
    }

    @Test func `a series has its tab row first, unless too few rows leave it out; a single question has none`() {
        #expect(layout(series()).tabs == 0)
        #expect(layout(series(), rows: 4).tabs == nil)
        let single = PendingQuestions(id: 1, questions: [series().questions[0]])
        #expect(layout(single).tabs == nil)
    }

    @Test func `the tab shown is drawn in the accent colour while the tabs have the focus, and only then`() throws {
        let pending = series(focus: .tabs, current: 1)
        let row = layout(pending).lines[0]
        let span = ScreenComposer.questionTabColumns(pending, columns: 120)[1]
        #expect(row.accents == [ScreenComposer.Accent(columns: span, style: Self.accent)])
        #expect(layout(series(focus: .choices, current: 1)).lines[0].accents.isEmpty)
        var reviewing = series(focus: .tabs)
        reviewing.reviewing = true
        #expect(layout(reviewing).lines[0].accents.isEmpty)
    }

    @Test func `the highlighted choice has the cursor and the accent while the choices have the focus`() throws {
        var pending = series(focus: .choices)
        pending.cursors[0] = 1
        let lines = layout(pending).lines
        let parser = try #require(lines.first { $0.text.contains("Parser") })
        let all = try #require(lines.first { $0.text.contains("All") })
        #expect(all.text.hasPrefix("  ›") && all.style == Self.accent)
        #expect(!parser.text.contains("›") && parser.style == .default)
        let unfocused = layout(series(focus: .tabs)).lines
        #expect(!unfocused.contains { $0.text.contains("›") && $0.text.contains("Parser") })
    }

    @Test func `a choice's meaning is dimmed, and a choice without one has no accent`() throws {
        let lines = layout(series()).lines
        let parser = try #require(lines.first { $0.text.contains("Parser") })
        let start = try #require(parser.text.firstRange(of: "only the parser")).lowerBound.utf16Offset(in: parser.text)
        #expect(
            parser.accents.contains {
                $0.style == Style(dim: true) && $0.columns.contains(start) && $0.columns.upperBound == parser.text.count
            }
        )
        #expect(try #require(lines.first { $0.text.contains("All") }).accents.isEmpty)
    }

    @Test func `the review says each answer: the labels chosen, nothing chosen, a note, or no answer`() {
        var pending = PendingQuestions(
            id: 1,
            questions: [
                ScreenQuestion(
                    question: "A?",
                    header: "Scope",
                    choices: [.init(label: "Parser"), .init(label: "Lexer")]
                ),
                ScreenQuestion(question: "B?", header: "Tests", choices: [.init(label: "Yes")]),
                ScreenQuestion(question: "C?", header: "Why", choices: [], note: .optional),
                ScreenQuestion(question: "D?", header: "Name", choices: [], note: .optional)
            ]
        )
        pending.chosen[0] = [0, 1]
        pending.notes[3].paste("keep it")
        pending.reviewing = true
        let text = layout(pending).lines.map(\.text)
        #expect(text.contains("  Scope: Parser, Lexer"))
        #expect(text.contains("  Tests: nothing chosen"))
        #expect(text.contains("  Why: no answer"))
        #expect(text.contains("  Name: note: keep it"))
        #expect(hint(pending) == "  Enter sends these answers · Esc goes back")
    }

    @Test func `the keys say what acts now`() {
        #expect(hint(series(focus: .tabs)) == "  ← → change question · Tab moves · Enter next · Esc declines")
        #expect(
            hint(series(focus: .choices)) == "  ↑ ↓ highlight · Space selects · Tab moves · Enter next · Esc declines"
        )
        #expect(
            hint(series(focus: .choices, current: 1))
                == "  ↑ ↓ highlight · Space checks several · Tab moves · Enter reviews · Esc declines"
        )
        #expect(hint(series(focus: .note, current: 1)).hasPrefix("  type a note · Tab moves"))
        let required = ScreenQuestion(question: "Why?", header: "Why", choices: [], note: .required)
        let alone = PendingQuestions(id: 1, questions: [required])
        #expect(hint(alone) == "  type the note (needed) · Enter answers · Esc declines")
    }
}
