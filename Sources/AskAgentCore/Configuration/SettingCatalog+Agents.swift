// The agents settings (roadmap 0063, ADR-0146), apart from SettingCatalog.swift to keep its body under the length limit.
extension SettingCatalog {
    static let agents: [Setting] = [
        row(
            "agents.enabled",
            .boolean,
            "true",
            "false",
            user: true,
            "Whether the model may start subagents with the agent tool. Only your own config file can turn it on."
        ),
        row(
            "agents.allowWrites",
            .boolean,
            "true",
            "false",
            user: true,
            "Whether subagents may change files; read-only otherwise."
        ),
        row("agents.maxTurns", .integer, "30", "30", "The most turns one subagent may take, from 1 to 200."),
        row(
            "agents.otherHarnesses",
            .boolean,
            "true",
            "false",
            user: true,
            "Whether other coding tools' agent definitions are read too, from their folders. Only your own config file can turn it on."
        ),
        row(
            "agents.resolveWithModel",
            .boolean,
            "false",
            "true",
            "Whether a cheap model on your connection classifies a definition's model words that no listed model matches."
        )
    ]
}
