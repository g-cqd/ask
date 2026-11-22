// The jobs settings (t232), each declared once (roadmap 0209).
// @dl:disable near-clone -- a section's settings are data: a key, its field, a type, an example, a default and help each
// @dl:disable structural-clone -- the same rows, matched by their shape
extension JobsSection: DeclaredSection {
    static let settings = SettingTable<JobsSection>(
        "jobs",
        [
            .limit(
                SettingCatalog.row(
                    "jobs.keepFinished",
                    .structured,
                    "200",
                    "null",
                    "How many finished jobs ask keeps for the job tool, with their output, the oldest let go first; null for all of them."
                ),
                \.keepFinished,
                least: 0
            )
        ]
    )
}
// @dl:enable near-clone
// @dl:enable structural-clone
