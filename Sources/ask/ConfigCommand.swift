internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask config`: the settings in force here, and where each came from.
struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config", abstract: "Show the effective configuration and where each value came from.")

    func run() {
        let source = ConfigurationSource.here
        let settings: RunSettings
        do { settings = try source.load() } catch { fail("ask: \(error)", code: 78) }
        let configuration = settings.configuration
        let rows: [(String, String, Configuration.Source)] = [
            ("provider", configuration.provider.value ?? "(the default)", configuration.provider.source),
            ("model", configuration.model.value ?? "(the provider's default)", configuration.model.source),
            ("maxTurns", String(configuration.maxTurns.value), configuration.maxTurns.source),
            ("compactAt", String(configuration.compactAt.value), configuration.compactAt.source)
        ]
        for (name, value, origin) in rows {
            print("\(name.padding(toLength: 10, withPad: " ", startingAt: 0))\(value)  [\(origin)]")
        }
        print("")
        print(
            "user file     \(source.loader.userPath)  \(status(of: source.loader.userPath, applied: settings.applied))")
        print(
            "project file  \(source.loader.projectPath)  \(status(of: source.loader.projectPath, applied: settings.applied))"
        )
        for notice in settings.notices { print("note: \(notice)") }
    }

    private func status(of path: String, applied: [String]) -> String {
        if applied.contains(path) { return "(applied)" }
        return FileManager.default.fileExists(atPath: path) ? "(ignored)" : "(none)"
    }
}
