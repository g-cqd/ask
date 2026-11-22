// The approvals settings (roadmap 0134), each declared once (roadmap 0209). Only the person's own file may set them, so a run takes
// the section whole from that file; each key still declares how it would combine.
// @dl:disable near-clone -- a section's settings are data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension ApprovalsSection: DeclaredSection {
    /// A section that sets nothing.
    public init() { self.init(defaultMode: nil) }

    static let settings = SettingTable<ApprovalsSection>(
        "approvals",
        [
            .choice(
                SettingCatalog.row(
                    "approvals.default",
                    .choice(["ask", "allow"]),
                    #""ask""#,
                    "ask",
                    user: true,
                    "What a call no list names does."
                ),
                \.defaultMode
            ),
            .list(
                SettingCatalog.row(
                    "approvals.allow",
                    .structured,
                    #"["mcp__docs__*"]"#,
                    "none",
                    user: true,
                    "Tools that run without asking."
                ),
                \.allow
            ),
            .list(
                SettingCatalog.row(
                    "approvals.ask",
                    .structured,
                    #"["write"]"#,
                    "none",
                    user: true,
                    "Tools that always ask."
                ),
                \.ask
            ),
            .choice(
                SettingCatalog.row(
                    "approvals.remember",
                    SettingCatalog.words(ApprovalsSection.Scope.self),
                    #""none""#,
                    "none",
                    user: true,
                    "What an \"always\" answer could write back to this file."
                ),
                \.scope
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
