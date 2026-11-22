// The hooks settings (roadmap 0192), declared with their section (`HooksSection+Settings.swift`, roadmap 0209).
extension SettingCatalog {
    static let hooks: [Setting] = HooksSection.settings.all.map(\.row)
}
