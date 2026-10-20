internal import ArgumentParser
internal import AskAI

/// Removes an alias; the model it named is untouched.
struct UnaliasConnectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "unalias", abstract: "Remove an alias.")

    @Argument(help: "The connection.") var name: String
    @Argument(help: "The alias to remove.") var alias: String

    func run() throws {
        let record = try NamedConnections.named(name)
        try NamedConnections.aliases(for: record).remove(alias)
        print("Removed \(record.name)/\(alias.lowercased()).")
    }
}
