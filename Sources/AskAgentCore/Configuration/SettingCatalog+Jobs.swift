// The jobs settings (t232), apart from SettingCatalog.swift to keep its body under the length limit.
extension SettingCatalog {
    static let jobs: [Setting] = [
        row(
            "jobs.keepFinished",
            .structured,
            "200",
            "null",
            "How many finished jobs ask keeps for the job tool, with their output, the oldest let go first; null for all of them."
        )
    ]
}
