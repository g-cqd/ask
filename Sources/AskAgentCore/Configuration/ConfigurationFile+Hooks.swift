extension ConfigurationFile {
    /// The `hooks` keys (roadmap 0192); unknown keys are refused.
    struct HooksDecoded: Decodable {
        var section = HooksSection()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    // @dl:accept -- a key table decoded by the shared walk, as every section's is; the keys are the data
                    case "maxContinues": section.maxContinues = try container.decode(Int.self, forKey: key)
                    default: throw UnknownKey(key: "hooks." + key.stringValue)
                }
            }
        }
    }

    /// Only the person's own file may say how long hooks keep a run going, and within 0 to 100.
    static func validateHooks(_ section: HooksSection?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let section else { return }
        if isProject {
            throw .outOfRange(
                path: path,
                key: "hooks",
                reason: "says how long hooks keep a run going: only your own config file can choose that"
            )
        }
        if let count = section.maxContinues, !(0 ... HooksSection.mostContinues).contains(count) {
            throw .outOfRange(
                path: path,
                key: "hooks.maxContinues",
                reason: "must be from 0 to \(HooksSection.mostContinues)"
            )
        }
    }
}
