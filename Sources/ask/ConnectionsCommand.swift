internal import ArgumentParser
internal import AskAI

/// Lists local names and credential presence, never remote account identities or tokens.
struct ConnectionsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connections", abstract: "List named subscription connections.",
        subcommands: [RenameConnectionCommand.self, RemoveConnectionCommand.self])

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
            print("\(record.name)  \(record.provider.rawValue)  \(present ? "credentials stored" : "signed out")")
        }
    }
}
