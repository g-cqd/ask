internal import ArgumentParser
internal import AskAI
internal import Foundation

/// `ask models codex`: explicitly refresh the selected account's catalog, not pi's static model list.
struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List a connection's available models. Supports codex and named Codex connections.")

    @Argument(help: "The connection to query: codex or a named Codex registration.") var connection = ProviderSettings
        .codex

    func run() async throws {
        let record = connection == ProviderSettings.codex ? nil : try NamedConnections.named(connection)
        guard record == nil || record?.provider == .codex else {
            throw ValidationError(
                "Catalog discovery currently supports Codex connections; other providers still accept --model.")
        }
        do {
            let snapshot =
                try await ModelDiscovery.codex(environment: ProcessInfo.processInfo.environment, connection: record)
                .models(now: Date().timeIntervalSince1970, refresh: true)
            for notice in snapshot.notices { FileHandle.standardError.write(Data("ask: \(notice)\n".utf8)) }
            print("MODEL                         CONTEXT       OUTPUT        REASONING")
            for (index, model) in snapshot.models.enumerated() {
                let id = (index == 0 ? "* " : "  ") + model.id
                let context = model.contextWindow.map(String.init) ?? "unknown"
                let output = model.maxOutputTokens.map(String.init) ?? "unknown"
                print(
                    id.padding(toLength: Swift.max(30, id.count + 1), withPad: " ", startingAt: 0)
                        + context.padding(toLength: 14, withPad: " ", startingAt: 0)
                        + output.padding(toLength: 14, withPad: " ", startingAt: 0) + model.reasoningDescription)
            }
            if let record { try printAliases(of: record) }
            print(
                "* default model when none is configured. REASONING: the levels this account reports; * marks the server's default."
            )
        } catch { fail("ask: \(error)", code: ModelDiscovery.exitCode(for: error)) }
    }

    /// The connection's own names, below the server's list, so what `--model` accepts is in one place.
    private func printAliases(of record: ConnectionRecord) throws {
        let aliases: ModelAliases
        do { aliases = try NamedConnections.aliases(for: record).load() } catch {
            FileHandle.standardError.write(Data("ask: aliases not shown: \(error)\n".utf8))
            return
        }
        guard !aliases.aliases.isEmpty || aliases.defaultModel != nil else { return }
        print("\nALIASES (yours, on \(record.name))")
        for (name, alias) in aliases.aliases.sorted(by: { $0.key < $1.key }) {
            let limits = [alias.contextWindow.map { "context \($0)" }, alias.maxOutputTokens.map { "max output \($0)" }]
                .compactMap { $0 }.joined(separator: ", ")
            print("  \(name) is \(alias.model)" + (limits.isEmpty ? "" : " (\(limits), as you stated)"))
        }
        if let model = aliases.defaultModel { print("  default: \(model)") }
    }
}
