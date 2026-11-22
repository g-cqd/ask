internal import ArgumentParser
internal import AskAgentCore
internal import AskSession
internal import AskTUI
internal import Foundation

/// `ask config`: the settings in force here, and where each came from.
struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show the effective configuration and where each value came from."
    )

    @Option(
        name: .customLong("mdm-schema"),
        help: ArgumentHelp(
            "Print the settings for an MDM console and stop: jamf (Jamf Pro's custom schema) or manifest (ProfileManifests, for iMazing Profile Editor and ProfileCreator).",
            valueName: "format"
        )
    )
    var mdmSchema: String?

    @Flag(
        name: .customLong("mdm-profile"),
        help:
            "Print a configuration profile (.mobileconfig) made of --requirements and --defaults, checked as ask reads them, and stop."
    )
    var mdmProfile = false

    @Option(help: ArgumentHelp("With --mdm-profile: what the organisation requires, a config.json.", valueName: "file"))
    var requirements: String?

    @Option(help: ArgumentHelp("With --mdm-profile: where people start, a config.json.", valueName: "file"))
    var defaults: String?

    @Option(help: ArgumentHelp("With --mdm-profile: the profile's identifier.", valueName: "id"))
    var identifier = "studio.aemi.ask.settings"

    @Option(help: ArgumentHelp("With --mdm-profile: the organisation the profile comes from.", valueName: "name"))
    var organization = "ask"

    func run() async {
        if let mdmSchema { return emit(schema: mdmSchema) }
        if mdmProfile { return emitProfile() }
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

extension ConfigCommand {
    /// `--mdm-schema`: the settings described for an MDM console (ADR-0168).
    private func emit(schema format: String) {
        let bytes: [UInt8]
        do {
            switch format {
                case "jamf": bytes = try ManagedSchema.jamf()
                case "manifest": bytes = try ManagedSchema.manifest(modified: Date())
                default: fail("ask: --mdm-schema takes jamf or manifest, not \(format)", code: 64)
            }
        } catch {
            fail("ask: \(error)", code: 1)
        }
        FileHandle.standardOutput.write(Data(bytes))
    }

    /// `--mdm-profile`: a `.mobileconfig` holding `--requirements` and `--defaults` (ADR-0168).
    private func emitProfile() {
        guard requirements != nil || defaults != nil else {
            fail("ask: --mdm-profile takes --requirements, --defaults or both", code: 64)
        }
        do {
            let profile = try ManagedSchema.profile(
                requirements: try requirements.map(read),
                defaults: try defaults.map(read),
                identifier: identifier,
                organization: organization
            )
            FileHandle.standardOutput.write(Data(profile))
        } catch {
            fail("ask: \(error)", code: 1)
        }
    }

    private func read(_ path: String) throws -> [UInt8] {
        guard let bytes = FileManager.default.contents(atPath: path) else {
            throw ConfigurationError.unreadable(path: path, errno: ENOENT)
        }
        return [UInt8](bytes)
    }
}
