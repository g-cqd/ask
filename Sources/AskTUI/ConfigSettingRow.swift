/// One row of the interactive configuration editor, supplied by the composition root.
public struct ConfigSettingRow: Sendable, Equatable {
    public let path: [String]
    public let title: String
    public let value: String
    public let choices: [String]
    public let editable: Bool

    public init(path: [String], title: String, value: String, choices: [String] = [], editable: Bool = false) {
        self.path = path
        self.title = title
        self.value = value
        self.choices = choices
        self.editable = editable
    }
}
