internal import AskCore

// The ui settings, first half of the catalog's order: what the page looks like and how ask behaves around it. The second half is in
// UISection+LayoutSettings.swift, so each file stays under the 250-line ceiling.
extension UISection: DeclaredSection {
    /// A section that sets nothing, for another target: the memberwise initializer Swift writes is internal.
    public static var empty: UISection { UISection() }

    /// Every `ui` setting, in the catalog's order: the order of `docs/config.example.jsonc`, the `/config` editor and `ask config`.
    static let settings = SettingTable("ui", page + layout)

    // @dl:disable near-clone -- the rows below are the ui settings' data: a key, its field, a type, an example, a default and help each
    // @dl:disable structural-clone -- the same rows, matched by their shape
    private static let page: [SettingDeclaration<UISection>] = [
        .flag(
            SettingCatalog.row("ui.mouse", .boolean, "true", "true", "ask handles clicks, selection and the wheel."),
            \.mouse
        ),
        .flag(
            SettingCatalog.row("ui.copyOnSelect", .boolean, "true", "true", "A finished selection is copied at once."),
            \.copyOnSelect
        ),
        .flag(
            SettingCatalog.row(
                "ui.tint",
                .boolean,
                "true",
                "true",
                "Tinted backgrounds for the input, your messages and tool calls."
            ),
            \.tint
        ),
        .flag(
            SettingCatalog.row(
                "ui.separator",
                .boolean,
                "true",
                "true",
                "A rule between the conversation and the input."
            ),
            \.separator
        ),
        .flag(
            SettingCatalog.row("ui.padding", .boolean, "true", "true", "A row of padding around each block."),
            \.padding
        ),
        .flag(
            SettingCatalog.row("ui.markdown", .boolean, "true", "true", "Markdown drawn everywhere it can be."),
            \.markdown
        ),
        .flag(
            SettingCatalog.row(
                "ui.highlight",
                .boolean,
                "true",
                "true",
                "Fenced code coloured by the language its fence names."
            ),
            \.highlight
        ),
        .flag(
            SettingCatalog.row("ui.shimmer", .boolean, "true", "true", "A running block's header shimmers."),
            \.shimmer
        ),
        .choice(
            SettingCatalog.row(
                "ui.dim",
                SettingCatalog.words(Dim.self),
                #""normal""#,
                "normal",
                "How faint secondary text is: ask's own grey, or nearer the page (faint, fainter), never below 3:1 contrast."
            ),
            \.dim
        ),
        .choice(
            SettingCatalog.row(
                "ui.sessionTint",
                SettingCatalog.words(SessionTint.self),
                #""both""#,
                "both",
                "Where the session's colour shows: the status line and the input's box, one of them, or none."
            ),
            \.sessionTint
        ),
        .choice(
            SettingCatalog.row(
                "ui.paths",
                SettingCatalog.words(PathsPreference.self),
                #""short""#,
                "short",
                "Paths in replies and reasoning shown relative to the project, or as written; linked either way."
            ),
            \.paths
        ),
        .limit(
            SettingCatalog.row(
                "ui.pathAncestors",
                .structured,
                "2",
                "2",
                "How many folders above the project a path may share one with to be shown from there, or null for no limit."
            ),
            \.pathAncestors,
            least: 0
        ),
        .limit(
            SettingCatalog.row(
                "ui.historyLimit",
                .structured,
                "2000",
                "null",
                "The most blocks the screen keeps, the oldest let go first, or null for all; the session file keeps everything."
            ),
            \.historyLimit,
            least: 1
        ),
        .flag(
            SettingCatalog.row(
                "ui.hover",
                .boolean,
                "true",
                "true",
                "What a click acts on brightens under the pointer."
            ),
            \.hover
        ),
        .flag(
            SettingCatalog.row(
                "ui.leaveFinishedJob",
                .boolean,
                "true",
                "true",
                "When a job you watch ends, go back to the conversation."
            ),
            \.jobAutoReturnWhenFocused
        ),
        .choice(
            SettingCatalog.row(
                "ui.sessionColor",
                SettingCatalog.words(SessionColorPreference.self),
                #""off""#,
                "off",
                "A colour of the session's own on the status line: always, or only while another ask runs."
            ),
            \.sessionColor
        ),
        .choice(
            SettingCatalog.row(
                "ui.notify",
                SettingCatalog.words(NotifyStyle.self),
                #""bell""#,
                "off",
                "While you look elsewhere, a bell or a notification when a turn ends or ask waits for your answer."
            ),
            \.notify
        ),
        // Stored the other way round: the field is whether lists leave the unusable models out.
        .field(
            SettingCatalog.row(
                "ui.listAllModels",
                .boolean,
                "false",
                "false",
                "Model lists also show models ask cannot use."
            ),
            \.onlyUsefulModels
        ) {
            !(try ConfigurationFile.decodeSwitch($0, key: $1, name: $2))
        } write: {
            $0 ? "false" : "true"
        }
    ]
    // @dl:enable near-clone
    // @dl:enable structural-clone
}
