// @dl:accept -- each section decodes its keys through the one shared walk; the key tables are the data
extension ConfigurationFile {
    /// The `skills` keys; unknown keys are refused.
    struct SkillsDecoded: Decodable {
        var section = SkillsSection()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "enabled": section.enabled = try container.decode(Bool.self, forKey: key)
                    case "maxAdvertised": section.maxAdvertised = try container.decode(Int.self, forKey: key)
                    case "sources": section.sources = try container.decode([String].self, forKey: key)
                    default: throw UnknownKey(key: "skills." + key.stringValue)
                }
            }
        }
    }

    /// A project's file may turn skills off and nothing else: a repository must not turn on, enlarge or redirect what the model is told to load.
    static func validateSkills(_ section: SkillsSection?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let section else { return }
        if let count = section.maxAdvertised, count < 0 {
            throw .outOfRange(path: path, key: "skills.maxAdvertised", reason: "must be 0 or more")
        }
        guard isProject else { return }
        if section.enabled == true {
            throw .outOfRange(path: path, key: "skills.enabled", reason: "a project's file may turn skills off, not on")
        }
        for (key, isSet) in [
            ("skills.maxAdvertised", section.maxAdvertised != nil), ("skills.sources", section.sources != nil)
        ]
        where isSet {
            throw .outOfRange(path: path, key: key, reason: "a project's file may only set skills.enabled to false")
        }
    }
}
