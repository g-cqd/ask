// @dl:accept -- two small commands that read best as their own sentences; a shared base would obscure each
internal import ArgumentParser
internal import AskAI

/// Chooses the model a connection uses when none is asked for, or clears the choice.
struct DefaultModelCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "default", abstract: "Choose the model a connection uses when none is asked for.")

    @Argument(help: "The connection.") var name: String
    @Argument(help: "An alias or a server model id.") var model: String?
    @Flag(help: "Forget the choice: the account's first listed model applies again.") var clear = false

    func validate() throws {
        guard (model != nil) != clear else { throw ValidationError("Give a model, or --clear, but not both.") }
    }

    func run() throws {
        let record = try NamedConnections.named(name)
        try NamedConnections.aliases(for: record).setDefault(clear ? nil : model)
        print(clear ? "\(record.name) has no default model." : "\(record.name) uses \(model ?? "") by default.")
    }
}
