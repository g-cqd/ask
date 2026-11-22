// The skills settings (roadmap 0061), each declared once (roadmap 0209).
// @dl:disable near-clone -- a section's settings are data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension SkillsSection: DeclaredSection {
    /// A section that sets nothing.
    init() { self.init(enabled: nil) }

    static let settings = SettingTable<SkillsSection>(
        "skills",
        [
            .flag(
                SettingCatalog.row(
                    "skills.enabled",
                    .boolean,
                    "true",
                    "true",
                    "Whether skills are offered; a project's file may only turn them off."
                ),
                \.enabled
            ),
            .number(
                SettingCatalog.row(
                    "skills.maxListed",
                    .integer,
                    "32",
                    "32",
                    user: true,
                    "How many skills are listed to the model."
                ),
                \.maxAdvertised
            ),
            .list(
                SettingCatalog.row(
                    "skills.sources",
                    .structured,
                    #"["agents", "user"]"#,
                    "every harness",
                    user: true,
                    "Where to look, by harness."
                ),
                \.sources
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
