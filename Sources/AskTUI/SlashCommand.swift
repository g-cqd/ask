/// A command typed into the prompt as `/name arguments`, rather than sent to the model.
public struct SlashCommand: Sendable, Equatable {
    /// The word after the slash: lowercase letters, digits and hyphens.
    public let name: String
    /// One line for `/help`.
    public let summary: String
    /// Whether the word after the command is chosen from a list the conversation offers (``Conversation/choices(for:)``): typing
    /// `/model ` opens it, narrowed by what follows, and Enter or a click runs the command with the row chosen.
    public let takesChoices: Bool

    /// A command called `name`.
    public init(name: String, summary: String, takesChoices: Bool = false) {
        self.name = name
        self.summary = summary
        self.takesChoices = takesChoices
    }
}
