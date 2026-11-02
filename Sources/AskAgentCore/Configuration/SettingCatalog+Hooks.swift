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
        ),
        row(
            "hooks.check",
            .text,
            #""swift test""#,
            "none",
            "A command run when a run that changed things would end; a failure is sent back to the model."
        ),
        row("hooks.checkTimeout", .integer, "600", "600", "How many seconds the check may take, from 1 to 600.")
    ]
}
