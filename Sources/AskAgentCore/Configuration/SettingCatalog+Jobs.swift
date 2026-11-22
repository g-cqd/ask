// The jobs settings (t232), declared with their section (roadmap 0209).
extension SettingCatalog {
    static let jobs: [Setting] = JobsSection.settings.all.map(\.row)
}
