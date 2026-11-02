// The hooks settings (roadmap 0192), apart from SettingCatalog.swift to keep its body under the length limit.
extension SettingCatalog {
    static let hooks: [Setting] = [
        row(
            "hooks.maxContinues",
            .integer,
            "3",
            "3",
            user: true,
            "How many times hooks may continue a run that would have ended; each counts against maxTurns."
        )
    ]
}
