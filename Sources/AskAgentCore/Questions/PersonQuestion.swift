/// A question the model asks the person (roadmap 0117): the words, a header of at most 12 characters for its tab, up to 8 choices,
/// whether several may be picked, and whether a note of their own is wanted.
public struct PersonQuestion: Sendable, Equatable {
    /// Who answers: given the questions, the answers in order, or nil when the person declined. Absent where no one can answer
    /// (`ask -p`), and then the tool is not offered.
    public typealias Asker = @Sendable ([PersonQuestion]) async -> [PersonAnswer]?

    /// Whether a note may, must, or cannot be written.
    public enum Note: String, Sendable, Equatable, CaseIterable { case optional, required, none }

    /// One choice: its words and, optionally, what it means.
    public struct Choice: Sendable, Equatable {
        public let label: String
        public let description: String?

        public init(label: String, description: String? = nil) {
            self.label = label
            self.description = description
            // @dl:accept -- the screen's ScreenQuestion mirrors this type on purpose: AskTUI cannot see AskAgentCore, so each side has its own (as approvals do)
        }
    }

    public let question: String
    public let header: String
    public let choices: [Choice]
    public let multiple: Bool
    public let note: Note

    public init(question: String, header: String, choices: [Choice], multiple: Bool = false, note: Note = .optional) {
        self.question = question
        self.header = header
        self.choices = choices
        self.multiple = multiple
        self.note = note
    }
}
