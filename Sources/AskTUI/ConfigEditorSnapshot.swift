/// The editor's rows and warnings, as the composition root last read them.
public struct ConfigEditorSnapshot: Sendable, Equatable {
    public let scope: String
    public let file: String
    public let rows: [ConfigSettingRow]
    public let warnings: [String]

    public init(scope: String, file: String, rows: [ConfigSettingRow], warnings: [String] = []) {
        self.scope = scope
        self.file = file
        self.rows = rows
        self.warnings = warnings
    }
}
