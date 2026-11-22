// The agents settings (roadmap 0063, ADR-0146), declared with their section (roadmap 0209).
extension SettingCatalog {
    static let agents: [Setting] = AgentsSection.settings.all.map(\.row)
}
