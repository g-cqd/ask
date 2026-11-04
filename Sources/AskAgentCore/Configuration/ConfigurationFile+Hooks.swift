extension ConfigurationFile {
    /// The `hooks` keys (roadmap 0192); unknown keys are refused.
    struct HooksDecoded: Decodable {
        // @dl:accept -- every section of the file is decoded and layered by the same idiom; its keys are the data
        var section = HooksSection()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "maxContinues": section.maxContinues = try container.decode(Int.self, forKey: key)
                    case "check": section.check = try container.decode(String.self, forKey: key)
                    // @dl:accept -- a key table decoded by the shared walk, as every section's is; the keys are the data
                    case "checkTimeout": section.checkTimeout = try container.decode(Int.self, forKey: key)
                    default: throw UnknownKey(key: "hooks." + key.stringValue)
                }
            }
        }
    }

    /// Only the person's own file says how long hooks keep a run going; a trusted project's may name its check. Counts within range.
    static func validateHooks(_ section: HooksSection?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let section else { return }
        func refuse(_ key: String, _ reason: String) -> ConfigurationError {
            .outOfRange(path: path, key: "hooks." + key, reason: reason)
        }
        func within(_ value: Int?, _ range: ClosedRange<Int>, _ key: String, _ unit: String) throws(ConfigurationError)
        {
            guard let value, !range.contains(value) else { return }
            throw refuse(key, "must be from \(range.lowerBound) to \(range.upperBound)\(unit)")
        }
        if isProject, section.maxContinues != nil {
            throw refuse(
                "maxContinues",
                "says how long hooks keep a run going: only your own config file can choose that"
            )
        }
        try within(section.maxContinues, 0 ... HooksSection.mostContinues, "maxContinues", "")
        if let check = section.check, check.allSatisfy(\.isWhitespace) { throw refuse("check", "must be a command") }
        try within(section.checkTimeout, 1 ... HooksSection.defaultCheckSeconds, "checkTimeout", " seconds")
    }
}
