// @dl:accept -- each section validates its keys on its own; the key tables are the data
extension ConfigurationFile {
    /// The sandbox section's paths must be absolute or start with `~/`, and a project's file may not widen it.
    static func validateSandbox(
        _ section: SandboxSection?,
        path: String,
        isProject: Bool
    ) throws(ConfigurationError) {
        guard let section else { return }
        func paths(_ settings: [PathSetting]) -> [String] {
            settings.flatMap { setting -> [String] in
                if case .paths(let paths) = setting { return paths }
                return []
            }
        }
        for (key, entries) in [
            ("sandbox.readable", section.allowRead), ("sandbox.hide", section.denyRead),
            ("sandbox.write", paths(section.write)), ("sandbox.read", paths(section.read))
        ] {
            for entry in entries where !(entry.hasPrefix("/") || entry == "~" || entry.hasPrefix("~/")) {
                throw .outOfRange(
                    path: path,
                    key: key,
                    reason: "has \"\(entry)\": use an absolute path, or one starting with ~/"
                )
            }
        }
        if isProject, !section.allowWrite.isEmpty {
            throw .outOfRange(
                path: path,
                key: "sandbox.writable",
                reason:
                    "can only be set in your own config file: a project that could open its own hooks would defeat it"
            )
        }
        if isProject, !section.allowRead.isEmpty {
            throw .outOfRange(
                path: path,
                key: "sandbox.readable",
                reason:
                    "can only be set in your own config file: a project that could widen the sandbox would defeat it"
            )
        }
    }

    /// The `sandbox` object: its two lists, and nothing else.
    // @dl:accept -- three key tables decoded the same way; the tables are the data, and the walk is already shared
    struct SandboxDecoded: Decodable {
        var section = SandboxSection()
        init(from decoder: any Decoder) throws {
            try ConfigurationFile.eachKey(of: decoder) { key, container in
                switch key.stringValue {
                    case "readable": section.allowRead = try container.decode([String].self, forKey: key)
                    case "writable": section.allowWrite = try container.decode([String].self, forKey: key)
                    case "hide": section.denyRead = try container.decode([String].self, forKey: key)
                    case "write": section.write = [try ConfigurationFile.scope(container, key, name: "sandbox.write")]
                    case "read": section.read = [try ConfigurationFile.scope(container, key, name: "sandbox.read")]
                    case "network":
                        let name = try container.decode(String.self, forKey: key)
                        guard let level = SandboxPolicy.Network(named: name) else {
                            throw BadValue(key: "sandbox.network", value: name)
                        }
                        section.network = level
                    default: throw UnknownKey(key: "sandbox." + key.stringValue)
                }
            }
        }
    }

    /// A write or read scope: "workspace", "anywhere", or a list of paths.
    static func scope(_ container: KeyedDecodingContainer<Key>, _ key: Key, name: String) throws -> PathSetting {
        guard let one = try? container.decode(String.self, forKey: key) else {
            return .paths(try container.decode([String].self, forKey: key))
        }
        switch one {
            case "workspace": return .workspace
            case "anywhere": return .anywhere
            default: throw BadValue(key: name, value: one)
        }
    }
}
