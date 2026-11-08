import Testing

@testable import AskTUI

/// Note n14: a series of up to 16 questions. Where the tab row is too narrow for every header, the question shown keeps its header in
/// full and the others show their initial, the review a ✓; where even that is too wide, as many as fit around the shown tab, `‹` and `›`
/// marking the cut ends. A
/// click still lands on the tab drawn under it.
@Suite("The question tabs fit a narrow row")
struct QuestionTabsTests {
    private static let words = [
        "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel",
        "India", "Juliett", "Kilo", "Lima", "Mike", "November", "Oscar", "Papa"
    ]

    private func pending(_ count: Int, current: Int = 0) -> PendingQuestions {
        var pending = PendingQuestions(
            id: 1,
            questions: Self.words.prefix(count)
                .map { ScreenQuestion(question: "Pick for \($0)?", header: $0, choices: [.init(label: "yes")]) }
        )
        pending.current = current
        return pending
    }

    private func row(_ pending: PendingQuestions, columns: Int) -> String {
        ScreenComposer.questionLayout(pending, columns: columns, rows: 30).lines[0].text
    }

    /// The text under each tab's span, trimmed.
    private func labels(_ pending: PendingQuestions, columns: Int) -> [String] {
        let text = Array(row(pending, columns: columns))
        return ScreenComposer.questionTabColumns(pending, columns: columns)
            .map { span in
                guard span.upperBound <= text.count else { return "" }
                return String(text[span].drop { $0 == " " }.reversed().drop { $0 == " " }.reversed())
            }
    }

    @Test func `where every header fits, the row is as before`() {
        #expect(row(pending(2), columns: 80) == "  [Alpha]   Bravo    ✓ Review ")
        #expect(labels(pending(2), columns: 80) == ["[Alpha]", "Bravo", "✓ Review"])
    }

    @Test func `where they do not, the shown one in full and the others by their initial`() {
        let shown = pending(8, current: 2)
        let text = row(shown, columns: 50)
        #expect(text.count <= 50 && text.contains("[Charlie]"), "\(text)")
        #expect(labels(shown, columns: 50) == ["A", "B", "[Charlie]", "D", "E", "F", "G", "H", "✓"], "\(text)")
    }

    @Test func `sixteen at eighty columns all show`() {
        let all = pending(16, current: 13)
        #expect(
            labels(all, columns: 80) == Self.words.map { String($0.first!) }.enumerated()
                .map { $0.offset == 13 ? "[November]" : $0.element } + ["✓"]
        )
    }

    @Test
    func `too narrow even for initials, the shown tab stays with its neighbours and marks where some are left out`() {
        let middle = pending(16, current: 7)
        let text = row(middle, columns: 40)
        #expect(
            text.count <= 40 && text.hasPrefix("  ‹ ") && text.hasSuffix(" ›") && text.contains("G  [Hotel]  I"),
            "\(text)"
        )
        #expect(ScreenComposer.questionTabColumns(middle, columns: 40).filter(\.isEmpty).count > 0)
    }

    @Test func `at the end, the row ends with the review`() {
        let last = pending(16, current: 15)
        let text = row(last, columns: 30)
        #expect(text.count <= 30 && text.contains("[Papa]"), "\(text)")
        let spans = ScreenComposer.questionTabColumns(last, columns: 30)
        #expect(spans.count == 17 && spans[0].isEmpty && labels(last, columns: 30)[15] == "[Papa]")
    }
}
