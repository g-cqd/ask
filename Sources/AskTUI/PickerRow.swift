/// One row of a picker: what it shows, a gloss beside it, and the text that replaces the typed word when it is chosen.
struct PickerRow: Sendable, Equatable {
    /// What the row shows first: `/config`, or a file's path.
    let label: String
    /// Said beside the label in a dimmer place of the same row; empty for none.
    let detail: String
    /// What the draft gets in place of the word that was typed, sigil included.
    let insertion: String

    /// A command: `/name`, its summary beside it.
    init(_ command: SlashCommand) {
        label = "/" + command.name
        detail = command.summary
        insertion = label
    }

    init(label: String, detail: String = "", insertion: String) {
        self.label = label
        self.detail = detail
        self.insertion = insertion
    }
}
