internal import ArgumentParser
internal import AskAI

/// Lists local names and credential presence, never remote account identities or tokens.
struct ConnectionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connections", abstract: "List named subscription connections.",
        subcommands: [
            RenameConnectionCommand.self, RemoveConnectionCommand.self, AliasConnectionCommand.self,
            UnaliasConnectionCommand.self, DefaultModelCommand.self
        ])

    func run() throws {
        let registry = NamedConnections.registry()
        let listing = try registry.list()
        NamedConnections.report(listing.notices)
        if listing.records.isEmpty { print("No named connections. Use `ask login codex --name work` to register one.") }
        for record in listing.records {
            let file = registry.credentials(for: record)
            let present: Bool
            switch record.provider {
                case .codex: present = try file.loadCodex(connection: record) != nil
                case .anthropic: present = try file.loadClaude(connection: record) != nil
            }
            let shared = present ? try sharing(of: record, in: registry)?.summary : nil
            print(
                "\(record.name)  \(record.provider.rawValue)  \(present ? "credentials stored" : "signed out")"
                    + (shared.map { "  (\($0))" } ?? ""))
        }
    }

    /// Which other sign-ins hold the same account as `record`, read from the stored credentials; the account itself is never shown.
    private func sharing(of record: ConnectionRecord, in registry: ConnectionRegistry) throws -> AccountSharing? {
        let file = registry.credentials(for: record)
        let identity: AccountIdentity?
        switch record.provider {
            case .codex: identity = try file.loadCodex(connection: record).map { .codex($0.accountID) }
            case .anthropic: identity = try file.loadClaude(connection: record)?.accountEmail.map { .claude($0) }
        }
        guard let identity else { return nil }
        return AccountSharing(
            connections: try registry.connections(as: identity, excluding: record),
            defaultSignIn: (try? CredentialFile.standard(environment: LaunchEnvironment.values).isSignedIn(as: identity))
                ?? false)
    }
}
