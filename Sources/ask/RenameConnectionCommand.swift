internal import ArgumentParser
internal import AskAI

/// Renaming changes a local label, never the credential or cache location.
struct RenameConnectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename", abstract: "Rename a connection without moving its credentials.")
    @Argument var name: String
    @Argument var newName: String

    func run() throws {
        let record = try NamedConnections.named(name)
        try NamedConnections.registry().rename(record, to: newName, reserved: NamedConnections.reserved())
        print("Renamed \(name) to \(newName.lowercased()). Update configuration references that use the old name.")
    }
}
