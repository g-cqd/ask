/// The model's questions while they wait (roadmap 0117): which one is shown, each one's cursor, checked choices and note, and whether
/// the review of every answer is shown. The note of the question shown lives in the input; the others are kept here.
public struct PendingQuestions: Sendable, Equatable {
    /// Which call asked, so the answers reach it.
    public let id: Int
    public let questions: [ScreenQuestion]
    /// The question shown.
    public internal(set) var current = 0
    /// Whether the review of every answer is shown, after the last question of a series.
    public internal(set) var reviewing = false
    var cursors: [Int]
    var chosen: [Set<Int>]
    var notes: [String]
    /// What the input held when the questions came; it is given back after.
    let draft: String
    /// Why Enter did not go on, shown under the question until the next key.
    var problem: String?

    init(id: Int, questions: [ScreenQuestion], draft: String) {
        self.id = id
        self.questions = questions
        self.draft = draft
        cursors = Array(repeating: 0, count: questions.count)
        chosen = Array(repeating: [], count: questions.count)
        notes = Array(repeating: "", count: questions.count)
    }

    /// Every answer, in order, with notes trimmed of surrounding blanks.
    var answers: [QuestionAnswer] {
        zip(chosen, notes).map { QuestionAnswer(chosen: $0.sorted(), note: Self.trimmed($1)) }
    }

    /// `text` without spaces, tabs and line ends at either end.
    static func trimmed(_ text: String) -> String {
        let isBlank: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" }
        return String(text.drop(while: isBlank).reversed().drop(while: isBlank).reversed())
    }

    /// Whether this is a series, which has tabs and a review.
    var isSeries: Bool { questions.count > 1 }
}
