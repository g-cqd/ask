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
        let lines = settings.report(userFile: source.loader.userPath, projectFile: source.loader.projectPath)
        for line in lines { print(line) }
    }
}
