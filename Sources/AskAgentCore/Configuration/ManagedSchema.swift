internal import AemiJSON

/// What an MDM console needs to draw ask's settings (roadmap 0130, ADR-0168, phase 4), generated from the catalog so it cannot drift:
/// a `requirements` and a `defaults` object, each holding every key a person may set (and `requirements` the managed-only `policy`),
/// each key with its type, its choices, its default where it is a plain value, and its help.
public enum ManagedSchema {
    /// One key as a console shows it.
    struct Key: Sendable, Equatable {
        let path: [String]
        let title: String
        let help: String
        /// The JSON types the key takes, the one its example has first.
        let types: [JSONType]
        let choices: [String]
        /// The catalog's example, as JSON.
        let example: JSONValue
        /// The default as JSON, when the catalog's is a plain value of the key's type; nil when it is a phrase ("the provider's
        /// default").
        let defaultValue: JSONValue?
    }

    /// JSON Schema's types, as a console names them.
    enum JSONType: String, Sendable, CaseIterable {
        case boolean, integer, number, string, array, object, null
    }

    /// The keys that take more than one JSON type, and which: a scope is a word or a list of paths, a limit a number or `null` for
    /// none. `ManagedSchemaTests` holds this to what ask's reader takes, key by key.
    static let moreTypes: [String: [JSONType]] = [
        "maxTurns": [.integer, .null], "compactAt": [.number, .integer], "ui.pathAncestors": [.integer, .null],
        "ui.historyLimit": [.integer, .null], "sandbox.write": [.string, .array], "sandbox.read": [.string, .array],
        "jobs.keepFinished": [.integer, .null]
    ]

    /// The keys of `rows`, each typed by its example (the catalog's kinds name what the editor does, not what a value is), or by
    /// ``moreTypes``.
    static func keys(_ rows: [SettingCatalog.Setting]) throws -> [Key] {
        try rows.map { row in
            let example = try JSONValue(AemiJSON.parse(Array(row.example.utf8)).root)
            let types = moreTypes[row.path.joined(separator: ".")] ?? [jsonType(of: example)]
            let type = types[0]
            let choices: [String] = if case .choice(let words) = row.kind { words } else { [] }
            return Key(
                path: row.path,
                title: row.path.joined(separator: "."),
                help: row.help,
                types: types,
                choices: choices,
                example: example,
                defaultValue: plainDefault(row.defaultValue, type: type, choices: choices)
            )
        }
    }

    private static func jsonType(of value: JSONValue) -> JSONType {
        switch value {
            case .bool: .boolean
            case .int: .integer
            case .number: .number
            case .string: .string
            case .array: .array
            default: .object
        }
    }

    /// The catalog's default as a value of `type`, when it is one: `true`, `20`, `0.75`, a choice's word.
    private static func plainDefault(_ text: String, type: JSONType, choices: [String]) -> JSONValue? {
        switch type {
            case .boolean: text == "true" ? .bool(true) : text == "false" ? .bool(false) : nil
            case .integer: Int64(text).map(JSONValue.int)
            case .number: Double(text).map(JSONValue.number)
            case .string: choices.contains(text) ? .string(text) : nil
            default: nil
        }
    }

    /// What a console may offer for `key`: its types without null, which a profile cannot carry.
    static func profileTypes(_ key: Key) -> [JSONType] {
        key.types.filter { $0 != .null }
    }

    /// The note a console shows for a key that also takes null.
    static func nullNote(_ key: Key) -> String {
        key.types.contains(.null)
            ? " null (no limit) cannot be sent in a profile: write it in requirements.json or defaults.json." : ""
    }

    /// The two documents' keys: every key a person may set in each, and `policy`'s in `requirements` only.
    static func documents() throws -> [(kind: ManagedFiles.Kind, keys: [Key])] {
        let shared = try keys(SettingCatalog.all)
        let managedOnly = try keys(SettingCatalog.managedOnly)
        return [(.requirements, shared + managedOnly), (.defaults, shared)]
    }
}
