extension Configuration {
    /// Where the `ui` or `skills` key `key` (`"ui.tint"`, `"skills.enabled"`) was last set, or `.defaults` when no layer set it. A section is
    /// layered key by key, so its keys can come from different files (roadmap 0103).
    public func source(ofKey key: String) -> Source { keySources[key] ?? .defaults }

    /// `self` with the `ui` and `skills` keys `file` sets attributed to `source`.
    func recordingKeySources(of file: ConfigurationFile, from source: Source) -> Configuration {
        var next = self
        if let section = file.ui {
            for key in UISection.keys where section.value(forKey: key) != nil { next.keySources["ui." + key] = source }
        }
        if let section = file.skills {
            for key in SkillsSection.keys where section.value(forKey: key) != nil {
                next.keySources["skills." + key] = source
            }
        }
        return next
    }
}
