// The skills settings (roadmap 0061), each declared once (roadmap 0209).
extension SkillsSection: DeclaredSection {
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
