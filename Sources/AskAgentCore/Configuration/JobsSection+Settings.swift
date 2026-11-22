// The jobs settings (t232), each declared once (roadmap 0209).
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
