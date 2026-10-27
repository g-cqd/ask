internal import AemiJSON

extension ConfigEditor {
    /// Removes keys ask does not know, so their values survive a save while known settings are validated whole.
    /// ADR-0032 still refuses those keys when ask loads the file; the editor only refuses not to delete them.
    static func stripped(_ value: JSONValue, path: [String]) -> (value: JSONValue, warnings: [String]) {
        guard case .object(let object) = value else { return (value, []) }
        let knownTop = Set(ConfigurationFile.keys)
        var kept = OrderedDictionary<String, JSONValue>()
        kept.reserveCapacity(object.count)
        var warnings: [String] = []
        for (key, child) in object {
            let childPath = path + [key]
            guard knownTop.contains(key) else {
                warnings.append(childPath.joined(separator: "."))
                continue
            }
            kept[key] = Self.strippedSection(child, path: childPath, section: key, warnings: &warnings)
        }
        return (.object(kept), warnings)
    }

    private static func strippedSection(
        _ value: JSONValue, path: [String], section: String, warnings: inout [String]
    ) -> JSONValue {
        guard case .object(let object) = value else { return value }
        let known: Set<String>
        switch section {
            case "sandbox": known = ["allowRead", "denyRead", "write", "read", "network"]
            case "ui": known = Set(UISection.keys)
            case "skills": known = Set(SkillsSection.keys)
            case "environment": known = ["pass", "withhold"]
            case "mcp": return Self.strippedServers(object, path: path, warnings: &warnings)
            default: return value
        }
        return .object(Self.filterKnown(object, known: known, path: path, warnings: &warnings))
    }

    /// Keeps the members whose names a section knows, warning about the rest without deleting them.
    private static func filterKnown(
        _ object: OrderedDictionary<String, JSONValue>, known: Set<String>, path: [String],
        warnings: inout [String]
    ) -> OrderedDictionary<String, JSONValue> {
        var kept = OrderedDictionary<String, JSONValue>()
        kept.reserveCapacity(object.count)
        for (key, child) in object {
            if known.contains(key) {
                kept[key] = child
            } else {
                warnings.append((path + [key]).joined(separator: "."))
            }
        }
        return kept
    }

    /// Under `mcp`, every member names a server; only the server's own keys are a fixed table.
    private static func strippedServers(
        _ object: OrderedDictionary<String, JSONValue>, path: [String], warnings: inout [String]
    ) -> JSONValue {
        let known = Set([
            "command", "args", "env", "cwd", "url", "headers", "tools", "enabled", "mode", "maxDirectTools"
        ])
        var kept = OrderedDictionary<String, JSONValue>()
        kept.reserveCapacity(object.count)
        for (server, value) in object {
            guard case .object(let fields) = value else {
                kept[server] = value
                continue
            }
            kept[server] = .object(
                Self.filterKnown(fields, known: known, path: path + [server], warnings: &warnings))
        }
        return .object(kept)
    }

    /// Sets `path` to `value`, creating objects on the way, or removes it for `.unset`.
    static func applying(_ value: Value, at path: [String], to root: JSONValue) -> JSONValue {
        if case .unset = value, path.count == 1, case .object(var object) = root {
            object.removeValue(forKey: path[0])
            return .object(object)
        }
        if path.isEmpty { return value.jsonValue ?? root }
        guard case .object(var object) = root else {
            var created = OrderedDictionary<String, JSONValue>()
            created[path[0]] = Self.applying(value, at: Array(path.dropFirst()), to: .object([:]))
            return .object(created)
        }
        let child = object[path[0]] ?? .object([:])
        object[path[0]] = Self.applying(value, at: Array(path.dropFirst()), to: child)
        return .object(object)
    }

    /// Encodes a value with the editor's stable JSON dialect: declaration order, strict JSON, detected layout.
    static func encoding(
        of value: JSONValue, pretty: Bool, indent: String, separator: JSONEncodingOptions.KeySeparator,
        trailingNewline: Bool
    ) throws -> [UInt8] {
        let options = JSONEncodingOptions(
            prettyPrinted: pretty, prettyKeySeparator: separator,
            indent: indent == "\t" ? .string("\t") : .spaces(indent.count))
        var bytes = try value.encodedBytes(options: options)
        if trailingNewline { bytes.append(0x0A) }
        return bytes
    }
}

extension ConfigEditor.Value {
    /// The JSON value to store, or nil for `unset`.
    var jsonValue: JSONValue? {
        switch self {
            case .unset: nil
            case .bool(let on): .bool(on)
            case .string(let text): .string(text)
        }
    }
}
