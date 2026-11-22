extension ConfigurationFile {
    /// Whether the file sets the key `name`.
    public func sets(_ name: String) -> Bool {
        if let setting = Self.settings.named[name] { return setting.write(self) != nil }
        return Self.sections[name]?.isSet(self) ?? false
    }
}
