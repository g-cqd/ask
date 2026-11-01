extension ConfigurationFile {
    /// `sessionEncryption`, `sessionCompression` or `sessionPassword` (roadmap 0182), read into this file.
    mutating func decodeSessionKey(_ key: Key, in container: KeyedDecodingContainer<Key>) throws {
        switch key.stringValue {
            case "sessionEncryption":
                sessionEncryption = try Self.decodeChoice(container, key: key, as: SessionEncryptionMode.self)
            case "sessionCompression":
                sessionCompression = try Self.decodeSwitch(container, key: key, name: "sessionCompression")
            default:
                sessionPassword = try Self.decodeChoice(container, key: key, as: SessionPasswordMode.self)
        }
    }

    /// Whether the file sets the session key `name`.
    func setsSessionKey(_ name: String) -> Bool {
        switch name {
            case "sessionEncryption": sessionEncryption != nil
            case "sessionCompression": sessionCompression != nil
            default: sessionPassword != nil
        }
    }
}
