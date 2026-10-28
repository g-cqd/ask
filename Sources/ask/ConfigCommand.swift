internal import ArgumentParser
internal import AskAgentCore
internal import AskTUI
internal import Foundation

/// `ask config`: the settings in force here, and where each came from.
struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config", abstract: "Show the effective configuration and where each value came from.")

    func run() async {
        let source = ConfigurationSource.here
        let settings: RunSettings
        do { settings = try await source.load(allowNetwork: false) } catch {
            fail("ask: \(error)", code: ModelDiscovery.exitCode(for: error))
        }
        let lines = settings.report(userFile: source.loader.userPath, projectFile: source.loader.projectPath)
        // Paths are written from `~`, as everywhere ask speaks (roadmap 0128).
        let home = LaunchEnvironment.values["HOME"]
        for line in lines { print(HomePath.abbreviate(line, home: home)) }
    }
}
