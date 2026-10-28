/// A command typed into the prompt as `/name arguments`, rather than sent to the model.
public struct SlashCommand: Sendable, Equatable {
    /// What a command is for, so the `/` picker can group commands under headings (roadmap 0079).
    public enum Category: String, Sendable, Equatable, CaseIterable {
        case session, model, tools, configuration

        /// The heading the picker draws above the category's first command.
        public var heading: String { rawValue }
    }

    /// The word after the slash: lowercase letters, digits and hyphens.
    public let name: String
    /// One line for `/help`.
    public let summary: String
    /// The group the command lists under in the picker.
    public let category: Category
    /// Whether the word after the command is chosen from a list the conversation offers (``Conversation/choices(for:)``): typing
    /// `/model ` opens it, narrowed by what follows, and Enter or a click runs the command with the row chosen.
    public let takesChoices: Bool

    /// A command called `name`.
    public init(name: String, summary: String, takesChoices: Bool = false, category: Category = .session) {
        self.name = name
        self.summary = summary
        self.takesChoices = takesChoices
        self.category = category
    }
}
