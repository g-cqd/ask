/// The person's answer to one question (roadmap 0117): the choices picked, by position, and their note, possibly empty.
public struct PersonAnswer: Sendable, Equatable {
    public let chosen: [Int]
    public let note: String

    public init(chosen: [Int], note: String) {
        self.chosen = chosen
        self.note = note
    }
}
