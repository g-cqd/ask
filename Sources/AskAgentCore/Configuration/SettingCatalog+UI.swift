// The ui settings come from their declarations (roadmap 0209), apart from SettingCatalog.swift.
extension SettingCatalog {
    static let ui: [Setting] = UISection.settings.all.map(\.row)
}
