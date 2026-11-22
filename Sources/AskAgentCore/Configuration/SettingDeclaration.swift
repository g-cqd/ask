/// One setting of a configuration section, declared once (roadmap 0209): its catalog row (name, type, example, default, help), how a
/// later layer's value combines with an earlier one's (``SettingMerge``), how a file's value is read into the section, how the section's
/// value is written back as a file writes it, and the layering that follows from its rule. A section's keys, `value(forKey:)`,
/// `layered(with:)`, its decoding and its catalog rows come from its ``SettingTable``.
struct SettingDeclaration<Section: Sendable>: Sendable {
    typealias Container = KeyedDecodingContainer<ConfigurationFile.Key>

    let row: SettingCatalog.Setting
    let merge: SettingMerge
    /// Reads the file's value at `key` (named `name` in an error) into the section.
    let read: @Sendable (inout Section, Container, ConfigurationFile.Key, String) throws -> Void
    /// The value as a file writes it, or nil when the section does not set it.
    let write: @Sendable (Section) -> String?
    /// Takes the later layer's value, where it sets one.
    let layer: @Sendable (inout Section, Section) -> Void

    /// The key under the section, as a file writes it: `fold.tools` under `ui`.
    var name: String { row.path.dropFirst().joined(separator: ".") }

    /// A catalog row: path, type, example, default and help.
    static func row(_ path: String, _ kind: SettingCatalog.Kind, _ example: String, _ value: String, _ help: String)
        -> SettingCatalog.Setting
    {
        SettingCatalog.row(path, kind, example, value, help)
    }

    /// A setting stored in one field, which a later layer's value replaces: read, written back and layered through `field`.
    static func field<Value: Sendable>(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, Value?> & Sendable,
        read: @escaping @Sendable (Container, ConfigurationFile.Key, String) throws -> Value,
        write: @escaping @Sendable (Value) -> String
    ) -> SettingDeclaration {
        SettingDeclaration(
            row: row,
            merge: .replaces,
            read: { section, container, key, name in section[keyPath: field] = try read(container, key, name) },
            write: { section in section[keyPath: field].map(write) },
            layer: { section, later in
                if let value = later[keyPath: field] { section[keyPath: field] = value }
            }
        )
    }

    /// An on/off setting: `true` or `false` (`"on"` and `"off"` still read).
    static func flag(_ row: SettingCatalog.Setting, _ field: any WritableKeyPath<Section, Bool?> & Sendable)
        -> SettingDeclaration
    {
        Self.field(row, field) {
            try ConfigurationFile.decodeSwitch($0, key: $1, name: $2)
        } write: {
            $0 ? "true" : "false"
        }
    }

    /// `true` or `false`, nothing else.
    static func bool(_ row: SettingCatalog.Setting, _ field: any WritableKeyPath<Section, Bool?> & Sendable)
        -> SettingDeclaration
    {
        Self.field(row, field) { container, key, _ in
            try container.decode(Bool.self, forKey: key)
        } write: {
            String($0)
        }
    }

    /// A list of words, written back separated by commas; a later layer's list replaces an earlier one's.
    static func list(_ row: SettingCatalog.Setting, _ field: any WritableKeyPath<Section, [String]?> & Sendable)
        -> SettingDeclaration
    {
        Self.field(row, field) { container, key, _ in
            try container.decode([String].self, forKey: key)
        } write: {
            $0.joined(separator: ", ")
        }
    }

    /// A protective list each layer adds to (``SettingMerge/adds``): kept sorted and without repeats, written back separated by
    /// commas, and nothing when empty.
    static func adds(_ row: SettingCatalog.Setting, _ field: any WritableKeyPath<Section, [String]> & Sendable)
        -> SettingDeclaration
    {
        SettingDeclaration(
            row: row,
            merge: .adds,
            read: { section, container, key, _ in
                section[keyPath: field] = Set(try container.decode([String].self, forKey: key)).sorted()
            },
            write: { section in
                let names = section[keyPath: field]
                return names.isEmpty ? nil : names.joined(separator: ", ")
            },
            layer: { section, later in
                section[keyPath: field] = Set(section[keyPath: field] + later[keyPath: field]).sorted()
            }
        )
    }

    /// A whole number.
    static func number(_ row: SettingCatalog.Setting, _ field: any WritableKeyPath<Section, Int?> & Sendable)
        -> SettingDeclaration
    {
        Self.field(row, field) { container, key, _ in
            try container.decode(Int.self, forKey: key)
        } write: {
            String($0)
        }
    }

    /// A limit: a whole number, `least` or more, or `null` for none, kept as -1.
    static func limit(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, Int?> & Sendable,
        least: Int
    ) -> SettingDeclaration {
        Self.field(row, field) {
            try ConfigurationFile.decodeCount($0, key: $1, named: $2, least: least)
        } write: {
            $0 == -1 ? "null" : String($0)
        }
    }

    /// One word of `Choice`'s cases.
    static func choice<Choice: RawRepresentable & Sendable>(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, Choice?> & Sendable
    ) -> SettingDeclaration where Choice.RawValue == String {
        Self.field(row, field) {
            try ConfigurationFile.decodeChoice($0, key: $1, as: Choice.self, named: $2)
        } write: {
            $0.rawValue
        }
    }

    /// One of `words`, kept and written back as it is.
    static func word(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, String?> & Sendable,
        _ words: [String]
    ) -> SettingDeclaration {
        Self.field(row, field) {
            try ConfigurationFile.word($0, $1, $2, words)
        } write: {
            $0
        }
    }

    /// One of two words, stored as whether it is the first.
    static func either(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, Bool?> & Sendable,
        _ yes: String,
        _ no: String
    ) -> SettingDeclaration {
        Self.field(row, field) {
            try ConfigurationFile.word($0, $1, $2, [yes, no]) == yes
        } write: {
            $0 ? yes : no
        }
    }

    /// Free text, written back as it is, or in quotes when `quoted`.
    static func string(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, String?> & Sendable,
        quoted: Bool = false
    ) -> SettingDeclaration {
        Self.field(row, field) { container, key, _ in
            try container.decode(String.self, forKey: key)
        } write: {
            quoted ? "\"\($0)\"" : $0
        }
    }

    /// Free text, written back in quotes; `check` reads it (and refuses what it must).
    static func text(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, String?> & Sendable,
        check: @escaping @Sendable (Container, ConfigurationFile.Key, String) throws -> String
    ) -> SettingDeclaration {
        Self.field(row, field, read: check) { "\"\($0)\"" }
    }
}
