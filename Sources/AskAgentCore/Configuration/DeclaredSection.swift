/// A configuration section whose settings are each declared once (roadmap 0209): reading a file, layering, `ask config`'s values and
/// the catalog come from its ``SettingTable``.
protocol DeclaredSection: Sendable {
    static var settings: SettingTable<Self> { get }
}

extension DeclaredSection {
    /// The value of `key` as a configuration file writes it, or nil when this section does not set it.
    func declaredValue(forKey key: String) -> String? {
        Self.settings.named[key]?.write(self)
    }

    /// `self` with each setting `later` sets combined by its own rule (``SettingMerge``).
    func declaredLayered(with later: Self) -> Self {
        var merged = self
        for setting in Self.settings.all { setting.layer(&merged, later) }
        return merged
    }

    /// Reads the file's value of the setting `name` (under the section) at `key`; an unknown name is refused.
    mutating func read(
        _ name: String,
        at key: ConfigurationFile.Key,
        in container: KeyedDecodingContainer<ConfigurationFile.Key>
    ) throws {
        let full = Self.settings.section + "." + name
        guard let setting = Self.settings.named[name] else { throw ConfigurationFile.UnknownKey(key: full) }
        try setting.read(&self, container, key, full)
    }
}
