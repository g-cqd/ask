/// A command typed into the prompt as `/name arguments`, rather than sent to the model.
public struct SlashCommand: Sendable, Equatable {
    /// What a command is for, so the `/` picker can group commands under headings (roadmap 0079).
    public enum Category: String, Sendable, Equatable, CaseIterable {
        case session, model, tools, configuration

        /// The heading the picker draws above the category's first command.
        public var heading: String { rawValue }
    }

    /// The word after the slash: lowercase letters, digits, hyphens and colons.
    public let name: String
    /// One line for `/help`.
    public let summary: String
    /// The group the command lists under in the picker.
    public let category: Category
    /// Whether the word after the command is chosen from a list the conversation offers (``Conversation/choices(for:)``): typing
    /// `/model ` opens it, narrowed by what follows, and Enter or a click runs the command with the row chosen.
    public let takesChoices: Bool
    /// What the command does when typed while a turn runs (roadmap 0113).
    public let duringTurn: DuringTurn

    /// What a command does when typed while a turn runs (roadmap 0113).
    public enum DuringTurn: Sendable, Equatable {
        /// Refused: the person stops the turn first.
        case refused
        /// Runs beside the turn, which goes on; what it changes applies from the turn's next request.
        case atOnce
        /// Waits for the turn's end, shown as waiting, and follows the queued messages' rules when the turn is stopped.
        case afterTurn
    }

    /// The names roadmap 0154 replaced, still typed: the old name runs the new command. `/tasks` was one, until it became the task
    /// list's (roadmap 0179).
    public static let renamed = ["tree": "rewind"]

    /// Subcommands belonging to a command in `commands` (e.g. `notes:edit` for `notes`).
    // @dl:accept -- a literal map of subcommand names shares the syntax of any dictionary literal
    public static let subcommands = [
        "notes:all": "notes",
        "notes:show": "notes",
        "notes:edit": "notes",
        "notes:add": "notes",
        "notes:delete": "notes",
        "notes:search": "notes"
    ]

    /// The command in `commands` called `name`, or the one an old name or `:subcommand` belongs to.
    public static func named(_ name: String, in commands: [SlashCommand]) -> SlashCommand? {
        if let exact = commands.first(where: { $0.name == name }) { return exact }
        if let target = renamed[name] { return commands.first { $0.name == target } }
        if let parent = subcommands[name], let base = commands.first(where: { $0.name == parent }) {
            let takesChoices = name == "notes:show" || name == "notes:edit" || name == "notes:delete"
            return SlashCommand(
                name: name,
                summary: base.summary,
                takesChoices: takesChoices,
                category: base.category,
                duringTurn: base.duringTurn
            )
        }
        return nil
    }

    /// A command called `name`.
    public init(
        name: String,
        summary: String,
        takesChoices: Bool = false,
        category: Category = .session,
        duringTurn: DuringTurn = .refused
    ) {
        self.duringTurn = duringTurn
        self.name = name
        self.summary = summary
        self.takesChoices = takesChoices
        self.category = category
    }
}
