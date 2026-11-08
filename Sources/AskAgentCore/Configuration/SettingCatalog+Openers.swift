// The openers settings (roadmap 0216, ADR-0148), apart from SettingCatalog.swift to keep its body under the length limit.
extension SettingCatalog {
    static let openers: [Setting] = [
        // @dl:accept -- catalog rows are data, one setting each
        row("openers.file", .text, #""Xcode""#, "the system's choice", user: true, "The app a clicked file opens in."),
        row(
            "openers.folder",
            .text,
            #""Finder""#,
            "the system's choice",
            user: true,
            "The app a clicked folder opens in."
        ),
        row(
            "openers.web",
            .text,
            #""Safari""#,
            "the system's choice",
            user: true,
            "The app a clicked web link opens in."
        ),
        row(
            "openers.rules",
            .structured,
            #"[{"match": {"extensions": ["md"]}, "app": "Typora"}]"#,
            "none",
            user: true,
            "Rules matching a clicked link to an app or a command, the first that matches winning."
        )
    ]
}

extension SettingCatalog {
    /// Every setting but the openers', section by section.
    static let beforeOpeners = top + ui + sandbox + approvals + hooks + threads + agents + skills + environment
}
