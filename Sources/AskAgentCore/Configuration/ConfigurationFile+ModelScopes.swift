extension ConfigurationFile {
    /// One `modelScopes` rule (roadmap 0094); unknown keys are refused, and the rule's sense is checked after decoding.
    struct ModelScopeDecoded: Decodable {
        /// The matchers, each one pattern; `providers` is the one list.
        private static let matchers: Set = ["path", "remote", "identity"]
        let scope: ModelScope

        init(from decoder: any Decoder) throws {
            var patterns: [String: String] = [:]
            var providers: [String] = []
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                let name = key.stringValue
                if name == "providers" {
                    providers = try container.decode([String].self, forKey: key)
                } else if Self.matchers.contains(name) {
                    patterns[name] = try container.decode(String.self, forKey: key)
                } else {
                    throw UnknownKey(key: "modelScopes." + name)
                }
            }
            scope = ModelScope(
                path: patterns["path"], remote: patterns["remote"], identity: patterns["identity"], providers: providers
            )
        }
    }

    /// Refuses the rules in a project's file, and a rule that matches nothing in particular or allows nothing.
    static func validateModelScopes(_ scopes: [ModelScope]?, path: String, isProject: Bool) throws(ConfigurationError) {
        guard let scopes else { return }
        if isProject {
            throw .outOfRange(
                path: path, key: "modelScopes",
                reason: "limits which providers serve your repositories: only your own config file can choose that")
        }
        for (index, scope) in scopes.enumerated() {
            let number = index + 1
            if scope.matchers.isEmpty || scope.matchers.contains(where: { $0.pattern.isEmpty }) {
                throw .outOfRange(
                    path: path, key: "modelScopes",
                    reason: "rule \(number) needs a non-empty path, remote or identity to match")
            }
            if scope.providers.isEmpty || scope.providers.contains(where: \.isEmpty) {
                throw .outOfRange(
                    path: path, key: "modelScopes", reason: "rule \(number) needs the providers it allows, by name")
            }
        }
    }
}
