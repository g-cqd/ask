internal import ArgumentParser
internal import AskAI
internal import Foundation

/// `ask models codex`: explicitly refresh the selected account's catalog, not pi's static model list.
struct ModelsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "models", abstract: "List a connection's available models. Currently supports codex.")

    @Argument(help: "The connection to query. Currently: codex.") var connection = ProviderSettings.codex

    func run() async throws {
        guard connection == ProviderSettings.codex else {
            throw ValidationError("Catalog discovery currently supports codex; other connections still accept --model.")
        }
        do {
            let snapshot = try await ModelDiscovery.codex(environment: ProcessInfo.processInfo.environment)
                .models(now: Date().timeIntervalSince1970, refresh: true)
            for notice in snapshot.notices { FileHandle.standardError.write(Data("ask: \(notice)\n".utf8)) }
            print("MODEL                         CONTEXT       OUTPUT")
            for (index, model) in snapshot.models.enumerated() {
                let id = (index == 0 ? "* " : "  ") + model.id
                let context = model.contextWindow.map(String.init) ?? "unknown"
                let output = model.maxOutputTokens.map(String.init) ?? "unknown"
                print(
                    id.padding(toLength: Swift.max(30, id.count + 1), withPad: " ", startingAt: 0)
                        + context.padding(toLength: 14, withPad: " ", startingAt: 0) + output)
            }
            print("* default when no model is configured; limits are reported by this account's catalog.")
        } catch { fail("ask: \(error)", code: ModelDiscovery.exitCode(for: error)) }
    }
}
