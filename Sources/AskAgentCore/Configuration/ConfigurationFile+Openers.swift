internal import AemiRegex

// @dl:accept -- every configuration section is decoded, layered and compared by the same idiom; the keys are the data
extension ConfigurationFile {
    /// The `openers` keys (roadmap 0216, ADR-0148); unknown keys are refused.
    struct OpenersDecoded: Decodable {
        // @dl:accept -- every configuration section is decoded by the same idiom; the keys are the data
        var section = OpenersSection()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    // @dl:accept -- key table rows, as every section decodes them
                    case "file": section.file = try container.decode(String.self, forKey: key)
                    case "folder": section.folder = try container.decode(String.self, forKey: key)
                    case "web": section.web = try container.decode(String.self, forKey: key)
                    case "rules": section.rules = try container.decode([RuleDecoded].self, forKey: key).map(\.rule)
                    default: throw UnknownKey(key: "openers." + key.stringValue)
                }
            }
        }
    }

    /// One rule: its `match`, and its `app` or `command`.
    struct RuleDecoded: Decodable {
        var rule = OpenerRule()

        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "match": rule = try container.decode(MatchDecoded.self, forKey: key).merged(into: rule)
                    case "app": rule.app = try container.decode(String.self, forKey: key)
                    case "command": rule.command = try container.decode([String].self, forKey: key)
                    default: throw UnknownKey(key: "openers.rules." + key.stringValue)
                }
            }
        }
    }

    /// A rule's criteria.
    struct MatchDecoded: Decodable {
        var kind: OpenerRule.Kind?
        var extensions: [String]?
        var host: String?
        var pattern: String?

        init(from decoder: any Decoder) throws {
            var kind: OpenerRule.Kind?
            var extensions: [String]?
            var host: String?
            var pattern: String?
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "kind":
                        kind = try ConfigurationFile.decodeChoice(
                            container,
                            key: key,
                            as: OpenerRule.Kind.self,
                            named: "openers.rules.match.kind"
                        )
                    case "extensions": extensions = try container.decode([String].self, forKey: key)
                    case "host": host = try container.decode(String.self, forKey: key)
                    case "pattern": pattern = try container.decode(String.self, forKey: key)
                    default: throw UnknownKey(key: "openers.rules.match." + key.stringValue)
                }
            }
            (self.kind, self.extensions, self.host, self.pattern) = (kind, extensions, host, pattern)
        }

        func merged(into rule: OpenerRule) -> OpenerRule {
            var rule = rule
            (rule.kind, rule.extensions, rule.host, rule.pattern) = (kind, extensions, host, pattern)
            return rule
        }
    }

    /// Openers are the person's own (ADR-0148): a project's file may not set them. Each rule names one app or one command, and its
    /// pattern compiles.
    // @dl:accept -- every section a project may not set is refused by the same idiom; the key and the reason are the data
    static func validateOpeners(_ section: OpenersSection?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let section else { return }
        if isProject {
            throw .outOfRange(
                path: path,
                key: "openers",
                reason: "chooses what a clicked link opens or runs: only your own config file can choose that"
            )
        }
        for (index, rule) in (section.rules ?? []).enumerated() {
            let key = "openers.rules[\(index)]"
            guard (rule.app == nil) != (rule.command == nil) else {
                throw .outOfRange(path: path, key: key, reason: "needs either an app or a command, and not both")
            }
            if let command = rule.command, let reason = OpenerRule.problem(in: command) {
                throw .outOfRange(path: path, key: key + ".command", reason: reason)
            }
            if let pattern = rule.pattern, (try? Pattern(pattern)) == nil {
                throw .outOfRange(path: path, key: key + ".match.pattern", reason: "is not a pattern AemiRegex reads")
            }
        }
    }
}
