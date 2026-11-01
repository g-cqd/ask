extension Configuration {
    /// The session keys of `file` over this configuration (roadmap 0182): a workspace's file overrides the user's either way.
    mutating func layerSessions(_ file: ConfigurationFile, from source: Source) {
        if let mode = file.sessionEncryption { sessionEncryption = Setting(value: mode, source: source) }
        if let compress = file.sessionCompression { sessionCompression = Setting(value: compress, source: source) }
        if let password = file.sessionPassword { sessionPassword = Setting(value: password, source: source) }
        if let scope = file.taskScope { taskScope = Setting(value: scope, source: source) }
    }
}
