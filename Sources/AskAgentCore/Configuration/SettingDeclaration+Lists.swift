// The builders for settings that hold lists, and the rules by which layers combine them.
extension SettingDeclaration {
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

    /// A protective list each layer adds to (``SettingMerge/adds``), written back separated by commas, and nothing when empty. Kept
    /// `sorted` and without repeats, or in the order the layers give it, each entry once more only when new.
    static func adds(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, [String]> & Sendable,
        sorted: Bool = false
    ) -> SettingDeclaration {
        SettingDeclaration(
            row: row,
            merge: .adds,
            read: { section, container, key, _ in
                let names = try container.decode([String].self, forKey: key)
                section[keyPath: field] = sorted ? Set(names).sorted() : names
            },
            write: { section in
                let names = section[keyPath: field]
                return names.isEmpty ? nil : names.joined(separator: ", ")
            },
            layer: { section, later in
                let names = section[keyPath: field]
                section[keyPath: field] =
                    sorted ? Set(names + later[keyPath: field]).sorted() : names.appendingNew(later[keyPath: field])
            }
        )
    }

    /// A scope each layer can only narrow (``SettingMerge/narrows``): one entry per layer that sets it, which those who use it
    /// intersect; an entry already present narrows nothing more, so it is kept once.
    static func narrows<Scope: Equatable & Sendable & CustomStringConvertible>(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, [Scope]> & Sendable,
        read: @escaping @Sendable (Container, ConfigurationFile.Key, String) throws -> Scope
    ) -> SettingDeclaration {
        SettingDeclaration(
            row: row,
            merge: .narrows,
            read: { section, container, key, name in section[keyPath: field] = [try read(container, key, name)] },
            write: { section in
                let scopes = section[keyPath: field]
                return scopes.isEmpty ? nil : scopes.map(\.description).joined(separator: ", ")
            },
            layer: { section, later in
                section[keyPath: field] = section[keyPath: field].appendingNew(later[keyPath: field])
            }
        )
    }

    /// A list a later layer replaces when it names anything; an empty list sets nothing.
    static func replacesWhenSet(
        _ row: SettingCatalog.Setting,
        _ field: any WritableKeyPath<Section, [String]> & Sendable
    )
        -> SettingDeclaration
    {
        SettingDeclaration(
            row: row,
            merge: .replaces,
            read: { section, container, key, _ in
                section[keyPath: field] = try container.decode([String].self, forKey: key)
            },
            write: { section in
                let names = section[keyPath: field]
                return names.isEmpty ? nil : names.joined(separator: ", ")
            },
            layer: { section, later in
                if !later[keyPath: field].isEmpty { section[keyPath: field] = later[keyPath: field] }
            }
        )
    }
}
