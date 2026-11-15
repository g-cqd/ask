/// Rows of the catalog kept beside it: the catalog's own body is at its length.
extension SettingCatalog {
    /// `codemode` (roadmap 0012, ADR-0156).
    static let codemode = row(
        "codemode",
        .boolean,
        "true",
        "true",
        "Whether the model may run one script over the tools in place of many calls."
    )

    /// `taskScope` (roadmap 0179, ADR-0140).
    static let taskScope = row(
        "taskScope",
        words(TaskScope.self),
        #""session""#,
        "session",
        "A task list for each session, or one for the workspace."
    )
}
