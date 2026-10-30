/// The person's answer to one of the model's questions (roadmap 0117): the choices checked, by position, and the note, possibly empty.
public struct QuestionAnswer: Sendable, Equatable {
    public let chosen: [Int]
    public let note: String

    public init(chosen: [Int], note: String) {
        self.chosen = chosen
        self.note = note
    }
}
