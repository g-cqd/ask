// The hooks settings (roadmap 0192), each declared once (roadmap 0209).
extension HooksSection: DeclaredSection {
    static let settings = SettingTable<HooksSection>(
        "hooks",
        [
            .number(
                SettingCatalog.row(
                    "hooks.maxContinues",
                    .integer,
                    "3",
                    "3",
                    user: true,
                    "How many times hooks may continue a run that would have ended; each counts against maxTurns."
                ),
                \.maxContinues
            ),
            .string(
                SettingCatalog.row(
                    "hooks.check",
                    .text,
                    #""swift test""#,
                    "none",
                    "A command run when a run that changed things would end; a failure is sent back to the model."
                ),
                \.check
            ),
            .number(
                SettingCatalog.row(
                    "hooks.checkTimeout",
                    .integer,
                    "600",
                    "600",
                    "How many seconds the check may take, from 1 to 600."
                ),
                \.checkTimeout
            )
        ]
    )
}
