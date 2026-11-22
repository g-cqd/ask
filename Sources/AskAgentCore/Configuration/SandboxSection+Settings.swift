// The sandbox settings (ADR-0035, roadmap 0042), each declared once (roadmap 0209), with how a later layer combines with an earlier
// one: what may be read or written again is replaced by the file that names it (only the person's own can), and everything else only
// narrows: hidden paths add up, write and read scopes are intersected, and the network takes the lower level.
extension SandboxSection: DeclaredSection {
    static let settings = SettingTable<SandboxSection>(
        "sandbox",
        [
            .narrows(
                SettingCatalog.row(
                    "sandbox.write",
                    .structured,
                    #""workspace""#,
                    "workspace",
                    "Where tools and commands may write."
                ),
                \.write
            ) { try ConfigurationFile.scope($0, $1, name: $2) },
            .narrows(
                SettingCatalog.row("sandbox.read", .structured, #""anywhere""#, "anywhere", "Where they may read."),
                \.read
            ) { try ConfigurationFile.scope($0, $1, name: $2) },
            network,
            .adds(
                SettingCatalog.row("sandbox.hide", .structured, #"["~/notes"]"#, "none", "More paths to hide."),
                \.denyRead
            ),
            .replacesWhenSet(
                SettingCatalog.row(
                    "sandbox.readable",
                    .structured,
                    #"["~/.aws"]"#,
                    "none",
                    user: true,
                    "Protected paths to make readable again."
                ),
                \.allowRead
            ),
            .replacesWhenSet(
                SettingCatalog.row(
                    "sandbox.writable",
                    .structured,
                    #"["~/.zshrc"]"#,
                    "none",
                    user: true,
                    "Protected paths to make writable again."
                ),
                \.allowWrite
            )
        ]
    )

    /// `sandbox.network`: how far commands reach; a layer can only lower it.
    private static let network = SettingDeclaration<SandboxSection>(
        row: SettingCatalog.row(
            "sandbox.network",
            .choice(["none", "localhost", "provider", "any"]),
            #""any""#,
            "any",
            "How far commands reach."
        ),
        merge: .narrows,
        read: { section, container, key, name in
            let word = try container.decode(String.self, forKey: key)
            guard let level = SandboxPolicy.Network(named: word) else {
                throw ConfigurationFile.BadValue(key: name, value: word)
            }
            section.network = level
        },
        write: { section in section.network.map { "\($0)" } },
        layer: { section, later in
            guard let lower = later.network else { return }
            section.network = section.network.map { Swift.min($0, lower) } ?? lower
        }
    )
}
