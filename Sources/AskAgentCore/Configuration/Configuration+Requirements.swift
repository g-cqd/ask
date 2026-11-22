extension Configuration {
    /// The document of the organisation that requires `key` (ADR-0168), or nil when nothing requires it. `key` is written in full
    /// (`model`, `ui.tint`, `mcp.docs.command`); a required key above it counts, so a required server locks each of its fields.
    public func requirement(of key: String) -> String? {
        var parts = key.split(separator: ".").map(String.init)
        while !parts.isEmpty {
            if let path = requiredKeys[parts.joined(separator: ".")] { return path }
            parts.removeLast()
        }
        return nil
    }

    /// `self` with what `file`, an organisation's requirements at `path`, sets recorded as required.
    func requiring(_ file: ConfigurationFile, from path: String) -> Configuration {
        var next = self
        for key in file.keysSet { next.requiredKeys[key] = path }
        return next
    }
}
