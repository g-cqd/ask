// @dl:accept -- each section decodes its own keys through the shared walk; the key tables are the data
extension ConfigurationFile {
    /// The `approvals` keys (roadmap 0134); unknown keys and values are refused.
    // @dl:accept -- each section decodes its own keys through the shared walk; the tables are the data
    struct ApprovalsDecoded: Decodable {
        var section = ApprovalsSection()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "default":
                        section.defaultMode = try ConfigurationFile.decodeChoice(
                            container, key: key, as: ApprovalsSection.Mode.self, named: "approvals.default")
                    case "scope":
                        section.scope = try ConfigurationFile.decodeChoice(
                            container, key: key, as: ApprovalsSection.Scope.self, named: "approvals.scope")
                    // @dl:accept -- a key table decoded by the shared walk; the keys are the data
                    case "allow": section.allow = try container.decode([String].self, forKey: key)
                    case "ask": section.ask = try container.decode([String].self, forKey: key)
                    default: throw UnknownKey(key: "approvals." + key.stringValue)
                }
            }
        }
    }
}
