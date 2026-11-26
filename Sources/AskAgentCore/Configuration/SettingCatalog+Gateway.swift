// The gateway settings (ADR-0170), declared with their section (roadmap 0209).
extension SettingCatalog {
    static let gateway: [Setting] = GatewaySection.settings.all.map(\.row)
}
