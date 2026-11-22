// The policy settings (ADR-0168), each declared once (roadmap 0209). Between the organisation's own documents, a later one replaces a
// key an earlier one set, as for every other key.
// @dl:disable near-clone -- a section's settings are data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension PolicySection: DeclaredSection {
    static let settings = SettingTable<PolicySection>(
        "policy",
        [
            .bool(
                SettingCatalog.row(
                    "policy.allowNoSandbox",
                    .boolean,
                    "false",
                    "true",
                    "Whether --no-sandbox and --yolo may turn the sandbox off."
                ),
                \.allowNoSandbox
            ),
            .bool(
                SettingCatalog.row(
                    "policy.allowYes",
                    .boolean,
                    "false",
                    "true",
                    "Whether --yes and --yolo may run every tool call without asking."
                ),
                \.allowYes
            ),
            .list(
                SettingCatalog.row(
                    "policy.providers",
                    .structured,
                    #"["work"]"#,
                    "any",
                    "The connections ask may use, by name; * matches anything."
                ),
                \.providers
            ),
            .list(
                SettingCatalog.row(
                    "policy.models",
                    .structured,
                    #"["team-model-*"]"#,
                    "any",
                    "The models ask may use, by id; * matches anything."
                ),
                \.models
            ),
            .list(
                SettingCatalog.row(
                    "policy.mcpServers",
                    .structured,
                    #"["https://mcp.example.com/*", "npx -y @example/*"]"#,
                    "any",
                    "The MCP servers ask may use, by URL or by command and arguments; * matches anything. Others are switched off."
                ),
                \.mcpServers
            ),
            .bool(
                SettingCatalog.row(
                    "policy.managedHooksOnly",
                    .boolean,
                    "true",
                    "false",
                    "Whether only the organisation's documents may set a hook command; one set anywhere else is off."
                ),
                \.managedHooksOnly
            ),
            .bool(
                SettingCatalog.row(
                    "policy.managedSkillsOnly",
                    .boolean,
                    "true",
                    "false",
                    "Whether skills come only from the organisation's skills folder, beside its requirements."
                ),
                \.managedSkillsOnly
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
