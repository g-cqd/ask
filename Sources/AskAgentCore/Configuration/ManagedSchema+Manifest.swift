internal import AemiJSON
public import Foundation

extension ManagedSchema {
    /// A ProfileManifests manifest (the format iMazing Profile Editor and ProfileCreator read: Apple's preference manifest with the
    /// `pfm_` keys), as an XML property list, for the domain `studio.aemi.ask`. `modified` is its `pfm_last_modified`.
    public static func manifest(modified: Date) throws -> [UInt8] {
        var subkeys: [[String: Any]] = []
        for (kind, keys) in try documents() {
            subkeys.append([
                "pfm_name": kind.rawValue,
                "pfm_title": kind == .requirements ? "Requirements" : "Defaults",
                "pfm_description":
                    kind == .requirements
                    ? "Applied after every other setting: nothing a person sets changes them."
                    : "Where a person starts: their own settings change them.",
                "pfm_type": "dictionary",
                "pfm_subkeys": tree(keys)
            ])
        }
        let manifest: [String: Any] = [
            "pfm_domain": ManagedProfile.domain,
            "pfm_title": "ask",
            "pfm_description": "Settings for ask, the terminal coding agent. Each key is the one config.json takes.",
            "pfm_format_version": 1,
            "pfm_version": 1,
            "pfm_interaction": "combined",
            "pfm_unique": true,
            "pfm_platforms": ["macOS"],
            "pfm_targets": ["system-managed", "user-managed"],
            "pfm_last_modified": modified,
            "pfm_subkeys": subkeys
        ]
        do {
            return [UInt8](try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0))
        } catch {
            preconditionFailure("a manifest of property-list values serializes: \(error)")
        }
    }

    /// `keys` nested by their paths, as `pfm_subkeys`, in the catalog's order.
    private static func tree(_ keys: [Key]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var seen: Set<String> = []
        for key in keys where !seen.contains(key.path[0]) {
            let name = key.path[0]
            seen.insert(name)
            let group = keys.filter { $0.path[0] == name && $0.path.count > 1 }
            if group.isEmpty {
                result.append(entry(key))
            } else {
                result.append([
                    "pfm_name": name, "pfm_title": name, "pfm_description": "", "pfm_type": "dictionary",
                    "pfm_subkeys": tree(group.map(Key.init(dropping:)))
                ])
            }
        }
        return result
    }

    /// One key. A key that takes several types is described by the first; its others, in the description.
    private static func entry(_ key: Key) -> [String: Any] {
        var entry: [String: Any] = [
            "pfm_name": key.path.last ?? key.title,
            "pfm_title": key.title,
            "pfm_description": key.help + alsoTakes(key) + nullNote(key),
            "pfm_type": pfmType(key.types[0])
        ]
        if !key.choices.isEmpty { entry["pfm_range_list"] = key.choices }
        if let value = key.defaultValue.flatMap(plistValue) {
            entry["pfm_default"] = value
        } else if let example = plistValue(key.example) {
            entry["pfm_value_placeholder"] = example
        }
        if key.types[0] == .array { entry["pfm_subkeys"] = [["pfm_type": "string"]] }
        return entry
    }

    /// The types beyond the first that a profile can carry, said in the description, since a manifest key has one type.
    private static func alsoTakes(_ key: Key) -> String {
        let others = profileTypes(key).dropFirst().map(\.rawValue)
        return others.isEmpty ? "" : " Also takes: \(others.joined(separator: ", "))."
    }

    private static func pfmType(_ type: JSONType) -> String {
        switch type {
            case .boolean: "boolean"
            case .integer: "integer"
            case .number: "real"
            case .string: "string"
            case .array: "array"
            case .object, .null: "dictionary"
        }
    }

    /// A plain JSON value as a property-list value; nil for an object, an array or null, which a placeholder does not show.
    private static func plistValue(_ value: JSONValue) -> Any? {
        switch value {
            case .bool(let flag): flag
            case .int(let number): number
            case .number(let number): number
            case .string(let text): text
            default: nil
        }
    }
}
