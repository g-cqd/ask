internal import ArgumentParser
internal import AskAI

/// Removal retires the stable id, so a future connection with the same name is not the same destination.
struct RemoveConnectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove", abstract: "Remove a named connection and its credentials.")
    @Argument var name: String

    func run() throws {
        let record = try NamedConnections.named(name)
        try NamedConnections.registry().remove(record)
        print("Removed \(record.name).")
    }
}
