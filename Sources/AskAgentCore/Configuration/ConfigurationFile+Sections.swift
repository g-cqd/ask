extension ConfigurationFile {
    /// A section at the top of a file: how a file's value is read into it, and whether a file sets it.
    struct SectionKey: Sendable {
        let read: @Sendable (inout ConfigurationFile, KeyedDecodingContainer<Key>, Key) throws -> Void
        let isSet: @Sendable (ConfigurationFile) -> Bool
        /// Each key under the section a file sets, written in full: `sandbox.write`, `mcp.docs`.
        let keys: @Sendable (ConfigurationFile) -> [String]

        /// A section whose settings are each declared once (roadmap 0209), read through its table.
        static func declared<Section: DeclaredSection>(
            _ field: any WritableKeyPath<ConfigurationFile, Section?> & Sendable
        )
            -> SectionKey
        {
            SectionKey(
                read: { file, container, key in
                    file[keyPath: field] = try container.decode(SectionDecoded<Section>.self, forKey: key).section
                },
                isSet: { $0[keyPath: field] != nil },
                keys: { file in
                    guard let section = file[keyPath: field] else { return [] }
                    let table = Section.settings
                    return table.all.filter { $0.write(section) != nil }.map { table.section + "." + $0.name }
                }
            )
        }
    }

    /// The sections, by their key in a file.
    // @dl:disable structural-clone -- one entry per section, each naming its own field: the table is the data
    // @dl:disable near-clone -- the same entries, matched by their text
    static let sections: [String: SectionKey] = [
        "sandbox": .declared(\.sandbox), "ui": .declared(\.ui), "skills": .declared(\.skills),
        "approvals": .declared(\.approvals),
        "hooks": .declared(\.hooks), "threads": .declared(\.threads), "agents": .declared(\.agents),
        "openers": .declared(\.openers), "jobs": .declared(\.jobs), "gateway": .declared(\.gateway),
        "policy": .declared(\.policy),
        "environment": .declared(\.environment),
        "mcp": SectionKey(
            read: { file, container, key in file.mcp = try container.decode(MCPDecoded.self, forKey: key).section },
            isSet: { $0.mcp != nil },
            keys: { file in
                guard let mcp = file.mcp else { return [] }
                return Set(mcp.servers.map(\.name) + mcp.masks.map(\.name)).sorted().map { "mcp." + $0 }
            }
        )
    ]
    // @dl:enable near-clone
    // @dl:enable structural-clone
}

extension ConfigurationFile {
    /// Every key this file sets, written in full (`model`, `ui.tint`, `sandbox.write`, `mcp.docs`): what a managed requirement locks.
    var keysSet: [String] {
        Self.settings.all.filter { $0.write(self) != nil }.map(\.name)
            + Self.sections.keys.sorted().flatMap { Self.sections[$0]?.keys(self) ?? [] }
    }
}
