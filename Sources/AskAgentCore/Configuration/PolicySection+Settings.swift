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
            ),
            .bool(
                SettingCatalog.row(
                    "policy.gatewayAllowed",
                    .boolean,
                    "false",
                    "true",
                    "Whether this computer may share its sessions with a gateway; false keeps gateway.enabled off."
                ),
                \.gatewayAllowed
            ),
            .bool(
                SettingCatalog.row(
                    "policy.gatewayApprovals",
                    .boolean,
                    "false",
                    "true",
                    "Whether a controller through the gateway may answer approvals; false leaves them to the computer."
                ),
                \.gatewayApprovals
            ),
            .bool(
                SettingCatalog.row(
                    "policy.gatewayStart",
                    .boolean,
                    "false",
                    "true",
                    "Whether a controller through the gateway may start sessions in gateway.folders."
                ),
                \.gatewayStart
            ),
            .string(
                SettingCatalog.row(
                    "policy.minimumVersion",
                    .text,
                    #""0.1.0-alpha.1""#,
                    "none",
                    "The oldest version of ask the organisation allows to run (SemVer 2.0)."
                ),
                \.minimumVersion,
                quoted: true
            ),
            .number(
                SettingCatalog.row(
                    "policy.sessionRetentionDays",
                    .integer,
                    "30",
                    "none",
                    "Days to keep recorded sessions before purging older ones at launch; 1 or more."
                ),
                \.sessionRetentionDays
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
