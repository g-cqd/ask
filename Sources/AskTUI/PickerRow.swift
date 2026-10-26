/// One row of a picker: what it shows, a gloss beside it, and the text that replaces the typed word when it is chosen.
struct PickerRow: Sendable, Equatable {
    /// What the row shows first: `/config`, or a file's path.
    let label: String
    /// Said beside the label in a dimmer place of the same row; empty for none.
    let detail: String
    /// What the draft gets in place of the word that was typed, sigil included.
    let insertion: String
    /// The arguments to run the command with at once, when the row is a choice and not text for the draft; nil for a row that inserts.
    let run: String?

    /// A command: `/name`, its summary beside it.
    init(_ command: SlashCommand) {
        label = "/" + command.name
        detail = command.summary
        insertion = label
        run = nil
    }

    init(label: String, detail: String = "", insertion: String) {
        self.label = label
        self.detail = detail
        self.insertion = insertion
        run = nil
    }

    /// A choice for `command`: chosen, it runs `command` with `arguments`.
    init(_ choice: ChoiceRow, command: String) {
        label = choice.isCurrent ? choice.label + " ●" : choice.label
        detail = choice.detail
        insertion = choice.completes ? choice.arguments : "/\(command) \(choice.arguments)"
        run = choice.completes ? nil : choice.arguments
    }
}
