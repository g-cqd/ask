/// A question the model asks the person (roadmap 0117), as the screen shows it: the words, a short header for its tab, the choices, whether
/// several may be checked, and whether a note is wanted.
public struct ScreenQuestion: Sendable, Equatable {
    /// Whether the person may, must, or cannot add words of their own.
    public enum Note: Sendable, Equatable { case optional, required, none }

    /// One choice: its words and, optionally, what it means.
    public struct Choice: Sendable, Equatable {
        public let label: String
        public let detail: String?

        public init(label: String, detail: String? = nil) {
            self.label = label
            self.detail = detail
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
