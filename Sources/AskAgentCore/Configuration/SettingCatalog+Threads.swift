// The threads settings (roadmap 0195), declared with their section (roadmap 0209).
extension SettingCatalog {
    static let threads: [Setting] = ThreadsSection.settings.all.map(\.row)
}
