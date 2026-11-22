/// A section's settings, each declared once (roadmap 0209), in the catalog's order, and by name for reading a file and `ask config`.
struct SettingTable<Section: Sendable>: Sendable {
    /// Every setting, in the order `docs/config.example.jsonc`, the `/config` editor and `ask config` show them.
    let all: [SettingDeclaration<Section>]
    /// The settings by their name under the section: `fold.tools`.
    let named: [String: SettingDeclaration<Section>]
    /// The section's key in a file: `ui`.
    let section: String

    init(_ section: String, _ all: [SettingDeclaration<Section>]) {
        self.section = section
        self.all = all
        named = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
    }
}
