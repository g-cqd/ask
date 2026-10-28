/// One row of a picker: what it shows, a gloss beside it, and the text that replaces the typed word when it is chosen.
struct PickerRow: Sendable, Equatable {
    /// What the row shows first: `/config`, or a file's path.
    let label: String
    /// Said beside the label in a dimmer place of the same row; empty for none.
    var detail: String
    /// What the draft gets in place of the word that was typed, sigil included.
    let insertion: String
    /// The arguments to run the command with at once, when the row is a choice and not text for the draft; nil for a row that inserts.
    let run: String?
    /// Whether the row is a group heading rather than a match: never selected, never chosen.
    var isHeading: Bool { label == Self.headingMark }

    /// The marker a heading row's label carries; a command cannot be called this.
    static let headingMark = "\u{7}heading"

    /// The setting path, for rows that commit a configuration value rather than insert text.
    let path: [String]
    /// The values left/right may cycle through; empty for a read-only row.
    let choices: [String]

    /// A command: `/name`, its summary beside it.
    init(_ command: SlashCommand) {
        label = "/" + command.name
        detail = command.summary
        insertion = label
        run = nil
        path = []
        choices = []
    }

    init(label: String, detail: String = "", insertion: String) {
        self.label = label
        self.detail = detail
        self.insertion = insertion
        run = nil
        path = []
        choices = []
    }

    /// A choice for `command`: chosen, it runs `command` with `arguments`.
    init(_ choice: ChoiceRow, command: String) {
        label = choice.isCurrent ? choice.label + " ●" : choice.label
        detail = choice.detail
        insertion = choice.completes ? choice.arguments : "/\(command) \(choice.arguments)"
        run = choice.completes ? nil : choice.arguments
        path = []
        choices = []
    }

    /// A group heading: drawn dim above the category's first match, never selectable.
    init(heading: String) {
        label = Self.headingMark
        detail = heading
        insertion = heading
        run = nil
        path = []
        choices = []
    }

    /// A configuration setting: its key, its value beside it, and the values it may cycle through.
    init(_ setting: ConfigSettingRow) {
        label = setting.title
        detail = setting.value
        insertion = setting.path.joined(separator: ".")
        run = nil
        path = setting.path
        choices = setting.choices
    }
}
