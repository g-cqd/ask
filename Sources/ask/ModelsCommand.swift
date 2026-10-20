internal import ArgumentParser
internal import AskAI
internal import Foundation

/// `ask models NAME`: read a connection's or provider's model list afresh, and keep it for the runs that follow.
struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models",
        abstract: "List the models a connection or provider offers, with the limits it states.")

    @Argument(help: "codex, a registered Codex connection, or a provider: a preset or a providers.json entry.")
    var connection = ProviderSettings.codex

    func run() async throws {
        let environment = ProcessInfo.processInfo.environment
        do {
            let now = Date().timeIntervalSince1970
            if let record = try registered(connection, environment: environment) {
                guard record.provider == .codex else { throw ValidationError("Only Codex connections list models.") }
                try await show(codex: record, now: now)
            } else if connection == ProviderSettings.codex {
                try await show(codex: nil, now: now)
            } else {
                try await show(provider: connection, environment: environment, now: now)
            }
        } catch { fail("ask: \(error)", code: ModelDiscovery.exitCode(for: error)) }
    }

    /// The registered connection called `name`, nil when none is: the name is then a provider's.
    private func registered(_ name: String, environment: [String: String]) throws -> ConnectionRecord? {
        guard name != ProviderSettings.codex, let canonical = ConnectionRecord.canonical(name) else { return nil }
        let listing = try NamedConnections.registry(environment: environment).list()
        NamedConnections.report(listing.notices)
        return listing.records.first { $0.name == canonical }
    }

    private func show(codex record: ConnectionRecord?, now: Double) async throws {
        let snapshot =
            try await ModelDiscovery.codex(environment: ProcessInfo.processInfo.environment, connection: record)
            .models(now: now, refresh: true)
        ModelTable.print(snapshot, defaultFirst: true)
        if let record { try printAliases(of: record) }
        print("* default model when none is configured.")
    }

    private func show(provider name: String, environment: [String: String], now: Double) async throws {
        let settings = try ProviderSettings.load(from: askConfigDirectory(environment: environment) + "/providers.json")
        let listing = try settings.listing(
            provider: name, environment: environment,
            storedKeys: { () throws(CredentialFileError) in
                try CredentialFile.standard(environment: environment).loadKeys().mapValues(\.key)
            })
        guard let listing else {
            throw ValidationError("\(name) has its own sign-in; this list covers providers reached with a key.")
        }
        let snapshot = try await ProviderModelDiscovery.catalog(for: listing, environment: environment)
            .models(now: now, refresh: true)
        ModelTable.print(snapshot, defaultFirst: false)
        print("No default: the provider does not say which model it prefers. Name one with --model.")
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
