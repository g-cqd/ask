// The openers settings (roadmap 0216, ADR-0148), each declared once (roadmap 0209). Only the person's own file may set them.
// @dl:disable near-clone -- a section's settings are data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension OpenersSection: DeclaredSection {
    /// A section that sets nothing.
    init() { self.init(file: nil) }

    static let settings = SettingTable<OpenersSection>(
        "openers",
        [
            .string(
                SettingCatalog.row(
                    "openers.file",
                    .text,
                    #""Xcode""#,
                    "the system's choice",
                    user: true,
                    "The app a clicked file opens in."
                ),
                \.file
            ),
            .string(
                SettingCatalog.row(
                    "openers.folder",
                    .text,
                    #""Finder""#,
                    "the system's choice",
                    user: true,
                    "The app a clicked folder opens in."
                ),
                \.folder
            ),
            .string(
                SettingCatalog.row(
                    "openers.web",
                    .text,
                    #""Safari""#,
                    "the system's choice",
                    user: true,
                    "The app a clicked web link opens in."
                ),
                \.web
            ),
            .field(
                SettingCatalog.row(
                    "openers.rules",
                    .structured,
                    #"[{"match": {"extensions": ["md"]}, "app": "Typora"}]"#,
                    "none",
                    user: true,
                    "Rules matching a clicked link to an app or a command, the first that matches winning."
                ),
                \.rules
            ) { container, key, _ in
                try container.decode([ConfigurationFile.RuleDecoded].self, forKey: key).map(\.rule)
            } write: {
                $0.count == 1 ? "1 rule" : "\($0.count) rules"
            }
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
