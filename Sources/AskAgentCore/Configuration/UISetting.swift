internal import AskCore

/// One `ui` setting, declared once (roadmap 0209): its catalog row (name, type, example, default, help), how a file's value is read
/// into a section, how a section's value is written back as a file writes it, and how a later layer's value replaces an earlier one.
/// `UISection.keys`, `value(forKey:)`, `layered(with:)`, the decoding and the catalog all come from ``UISetting/all``.
struct UISetting: Sendable {
    typealias Container = KeyedDecodingContainer<ConfigurationFile.Key>

    let row: SettingCatalog.Setting
    /// Reads the file's value at `key` (named `name` in an error) into the section.
    let read: @Sendable (inout UISection, Container, ConfigurationFile.Key, String) throws -> Void
    /// The value as a file writes it, or nil when the section does not set it.
    let write: @Sendable (UISection) -> String?
    /// Takes the later layer's value, where it sets one.
    let layer: @Sendable (inout UISection, UISection) -> Void

    /// The key under `ui`, as a file writes it: `fold.tools`.
    var name: String { row.path.dropFirst().joined(separator: ".") }

    /// A catalog row under `ui`: path, type, example, default and help.
    static func row(_ path: String, _ kind: SettingCatalog.Kind, _ example: String, _ value: String, _ help: String)
        -> SettingCatalog.Setting
    {
        SettingCatalog.row(path, kind, example, value, help)
    }

    /// A setting stored in one field: read, written back and layered through `field`.
    static func field<Value: Sendable>(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<UISection, Value?> & Sendable,
        read: @escaping @Sendable (Container, ConfigurationFile.Key, String) throws -> Value,
        write: @escaping @Sendable (Value) -> String
    ) -> UISetting {
        UISetting(
            row: row,
            read: { section, container, key, name in section[keyPath: field] = try read(container, key, name) },
            write: { section in section[keyPath: field].map(write) },
            layer: { section, later in
                if let value = later[keyPath: field] { section[keyPath: field] = value }
            }
        )
    }

    /// An on/off setting: `true` or `false` (`"on"` and `"off"` still read).
    static func flag(_ row: SettingCatalog.Setting, _ field: any WritableKeyPath<UISection, Bool?> & Sendable)
        -> UISetting
    {
        Self.field(row, field) {
            try ConfigurationFile.decodeSwitch($0, key: $1, name: $2)
        } write: {
            $0 ? "true" : "false"
        }
    }

    /// A whole number.
    static func number(_ row: SettingCatalog.Setting, _ field: any WritableKeyPath<UISection, Int?> & Sendable)
        -> UISetting
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
        _ field: any WritableKeyPath<UISection, Int?> & Sendable,
        least: Int
    ) -> UISetting {
        Self.field(row, field) {
            try ConfigurationFile.decodeCount($0, key: $1, named: $2, least: least)
        } write: {
            $0 == -1 ? "null" : String($0)
        }
    }

    /// One word of `Choice`'s cases.
    static func choice<Choice: RawRepresentable & Sendable>(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<UISection, Choice?> & Sendable
    ) -> UISetting where Choice.RawValue == String {
        Self.field(row, field) {
            try ConfigurationFile.decodeChoice($0, key: $1, as: Choice.self, named: $2)
        } write: {
            $0.rawValue
        }
    }

    /// One of two words, stored as whether it is the first.
    static func either(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<UISection, Bool?> & Sendable,
        _ yes: String,
        _ no: String
    ) -> UISetting {
        Self.field(row, field) {
            try ConfigurationFile.word($0, $1, $2, [yes, no]) == yes
        } write: {
            $0 ? yes : no
        }
    }

    /// Free text, written back in quotes; `check` reads it (and refuses what it must).
    static func text(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<UISection, String?> & Sendable,
        check: @escaping @Sendable (Container, ConfigurationFile.Key, String) throws -> String
    ) -> UISetting {
        Self.field(row, field, read: check) { "\"\($0)\"" }
    }
}
