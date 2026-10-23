internal import ArgumentParser
internal import AskAI
internal import Foundation

/// Gives a model on one connection a name of the user's own; the server's id is what is sent.
struct AliasConnectionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alias", abstract: "Give a model on a connection a name of your own.",
        discussion: "ask connections alias work fast gpt-6-luna, then ask --provider work --model fast.")

    @Argument(help: "The connection.") var name: String
    @Argument(help: "The alias: letters, digits, dots, underscores and hyphens.") var alias: String
    @Argument(help: "The server's own model id.") var model: String
    @Option(name: .customLong("context"), help: "A context window to use for this alias instead of the server's.")
    var context: Int?
    @Option(name: .customLong("max-output"), help: "A longest reply to use for this alias.") var maxOutput: Int?
    // Not `--thinking`: the root command has that option, and ArgumentParser gives it to the root, silently dropping it here.
    @Option(
        name: .customLong("thinking-level"),
        help: "A thinking level for this alias: \(ThinkingLevel.choices). --thinking and ASK_THINKING still win.")
    var thinking: String?

    func validate() throws {
        if let thinking, ThinkingLevel(rawValue: thinking) == nil {
            throw ValidationError("--thinking-level must be one of: \(ThinkingLevel.choices).")
        }
    }

    func run() throws {
        let record = try NamedConnections.named(name)
        // The cached list, when there is one, so an alias cannot hide a model the account offers.
        let known =
            record.provider == .codex
            ? ((try? ModelDiscovery.codex(environment: ProcessInfo.processInfo.environment, connection: record)
                .cached(now: Date().timeIntervalSince1970))??
                .models.map(\.id) ?? []) : []
        try NamedConnections.aliases(for: record)
            .set(
                alias, to: model, contextWindow: context, maxOutputTokens: maxOutput,
                thinking: thinking.flatMap(ThinkingLevel.init(rawValue:)), known: known)
        print("\(record.name)/\(alias.lowercased()) is \(model)" + (thinking.map { ", thinking \($0)" } ?? "") + ".")
    }
}
