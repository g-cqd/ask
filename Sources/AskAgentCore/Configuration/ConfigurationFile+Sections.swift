extension ConfigurationFile {
    /// A section at the top of a file: how a file's value is read into it, and whether a file sets it.
    struct SectionKey: Sendable {
        let read: @Sendable (inout ConfigurationFile, KeyedDecodingContainer<Key>, Key) throws -> Void
        let isSet: @Sendable (ConfigurationFile) -> Bool

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
                isSet: { $0[keyPath: field] != nil }
            )
        }
    }

    /// The sections, by their key in a file.
    // @dl:disable structural-clone -- one entry per section, each naming its own field: the table is the data
    static let sections: [String: SectionKey] = [
        "sandbox": .declared(\.sandbox), "ui": .declared(\.ui), "skills": .declared(\.skills),
        "approvals": .declared(\.approvals),
        "hooks": .declared(\.hooks), "threads": .declared(\.threads), "agents": .declared(\.agents),
        "openers": .declared(\.openers), "jobs": .declared(\.jobs), "environment": .declared(\.environment),
        "mcp": SectionKey(
            read: { file, container, key in file.mcp = try container.decode(MCPDecoded.self, forKey: key).section },
            isSet: { $0.mcp != nil }
        )
    ]
    // @dl:enable structural-clone
}
