/// A command typed into the prompt as `/name arguments`, rather than sent to the model.
public struct SlashCommand: Sendable, Equatable {
    /// The word after the slash: lowercase letters, digits and hyphens.
    public let name: String
    /// One line for `/help`.
    public let summary: String

    /// A command called `name`.
    public init(name: String, summary: String) {
        self.name = name
        self.summary = summary
    }
}
