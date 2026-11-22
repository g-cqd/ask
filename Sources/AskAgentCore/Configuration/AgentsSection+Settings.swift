// The agents settings (roadmap 0063, ADR-0146), each declared once (roadmap 0209).
extension AgentsSection: DeclaredSection {
    // @dl:disable near-clone -- the rows below are the settings' data: a key, its field, a type, an example, a default and help each
    // @dl:disable structural-clone -- the same rows, matched by their shape
    static let settings = SettingTable<AgentsSection>(
        "agents",
        [
            .bool(
                SettingCatalog.row(
                    "agents.enabled",
                    .boolean,
                    "true",
                    "false",
                    user: true,
                    "Whether the model may start subagents with the agent tool. Only your own config file can turn it on."
                ),
                \.enabled
            ),
            .bool(
                SettingCatalog.row(
                    "agents.allowWrites",
                    .boolean,
                    "true",
                    "false",
                    user: true,
                    "Whether subagents may change files; read-only otherwise."
                ),
                \.allowWrites
            ),
            .number(
                SettingCatalog.row(
                    "agents.maxTurns",
                    .integer,
                    "30",
                    "30",
                    "The most turns one subagent may take, from 1 to 200."
                ),
                \.maxTurns
            ),
            .bool(
                SettingCatalog.row(
                    "agents.otherHarnesses",
                    .boolean,
                    "true",
                    "false",
                    user: true,
                    "Whether other coding tools' agent definitions are read too, from their folders. Only your own config file can turn it on."
                ),
                \.otherHarnesses
            ),
            .bool(
                SettingCatalog.row(
                    "agents.resolveWithModel",
                    .boolean,
                    "false",
                    "true",
                    "Whether a cheap model on your connection classifies a definition's model words that no listed model matches."
                ),
                \.resolveWithModel
            )
        ]
    )
    // @dl:enable near-clone
    // @dl:enable structural-clone
}
