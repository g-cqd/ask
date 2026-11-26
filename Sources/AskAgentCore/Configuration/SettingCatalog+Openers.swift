// The openers settings (roadmap 0216, ADR-0148), declared with their section (roadmap 0209).
extension SettingCatalog {
    static let openers: [Setting] = OpenersSection.settings.all.map(\.row)
}

extension SettingCatalog {
    /// Every setting but the openers', section by section.
    static let beforeOpeners =
        top + ui + sandbox + approvals + hooks + threads + agents + skills + environment + jobs + gateway
}

extension SettingCatalog {
    /// The settings only an organisation's requirements may hold (ADR-0168): not in ``all``, which lists what a person may set.
    static let managedOnly: [Setting] = PolicySection.settings.all.map(\.row)
}
