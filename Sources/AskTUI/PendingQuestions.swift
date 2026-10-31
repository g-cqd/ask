/// The model's questions while they wait (roadmap 0117): which one is shown, what has the focus, each one's highlighted choice, checked
/// choices and note, and whether the review of every answer is shown. Each question's note is its own small editor, a row of the
/// section; the input below keeps the person's draft (owner, 2026-10-31).
public struct PendingQuestions: Sendable, Equatable {
    /// What takes the keys: the row of tabs (a series only), the choices, or the note row.
    public enum Focus: Sendable, Equatable { case tabs, choices, note }

    /// Which call asked, so the answers reach it.
    public let id: Int
    public let questions: [ScreenQuestion]
    /// The question shown.
    public internal(set) var current = 0
    /// Whether the review of every answer is shown, after the last question of a series.
    public internal(set) var reviewing = false
    /// What takes the keys in the question shown.
    public internal(set) var focus: Focus
    var cursors: [Int]
    var chosen: [Set<Int>]
    var notes: [PromptEditor]
    /// Why Enter did not go on, shown under the question until the next key.
    var problem: String?

    init(id: Int, questions: [ScreenQuestion]) {
        self.id = id
        self.questions = questions
        cursors = Array(repeating: 0, count: questions.count)
        chosen = Array(repeating: [], count: questions.count)
        notes = Array(repeating: PromptEditor(), count: questions.count)
        focus = questions.first.map(Self.opening) ?? .choices
    }

    /// Every answer, in order, with notes trimmed of surrounding blanks.
    var answers: [QuestionAnswer] {
        zip(chosen, notes).map { QuestionAnswer(chosen: $0.sorted(), note: Self.trimmed($1.text)) }
    }

    /// `text` without spaces, tabs and line ends at either end.
    static func trimmed(_ text: String) -> String {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" }
        return String(text.drop(while: isBlank).reversed().drop(while: isBlank).reversed())
    }

    /// Whether this is a series, which has tabs and a review.
    var isSeries: Bool { questions.count > 1 }

    /// Where a question opens: its choices, or its note when it has none.
    static func opening(_ question: ScreenQuestion) -> Focus {
        !question.choices.isEmpty ? .choices : question.note != .none ? .note : .choices
    }

    /// What Tab moves through on the question shown, in order: the tabs of a series, the choices, the note row.
    var focusOrder: [Focus] {
        let question = questions[current]
        return (isSeries ? [.tabs] : []) + (question.choices.isEmpty ? [] : [.choices])
            + (question.note == .none ? [] : [.note])
    }

    /// The focus `step` places after the current one in ``focusOrder``, wrapping.
    mutating func moveFocus(by step: Int) {
        if let next = focusOrder.cycled(from: focus, by: step) { focus = next }
    }
}
