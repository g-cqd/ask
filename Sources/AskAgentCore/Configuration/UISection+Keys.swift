extension UISection {
    /// The value of `key` as a configuration file writes it (`true`, `words`, `3`; free text in quotes), or nil when this section does not set it. The
    /// names are those of ``keys``, so `ask config` can show each key under the name a person types (roadmaps 0103 and 0154). Each
    /// setting's own declaration writes it (``UISetting``, roadmap 0209).
    public func value(forKey key: String) -> String? {
        UISetting.named[key]?.write(self)
    }
}
