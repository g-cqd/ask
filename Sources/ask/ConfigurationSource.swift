internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Where a run's settings come from, and how to read them again: the loader, the command-line flags that stay
/// the highest layer across reloads, and `providers.json`.
struct ConfigurationSource: Sendable {
    let loader: ConfigurationLoader
    let providersPath: String
    let flags: Flags
    let environment: [String: String]

    /// The flags the user gave; nil for one not given.
    struct Flags: Sendable {
        var model: String?
        var provider: String?
        var maxTurns: Int?
        var compactAt: Int?
    }

    /// The source for the project at `workingDirectory`.
    init(workingDirectory: String, flags: Flags, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let directory = askConfigDirectory(environment: environment)
        loader = ConfigurationLoader(project: workingDirectory, configDirectory: directory, environment: environment)
        providersPath = directory + "/providers.json"
        self.flags = flags
        self.environment = environment
    }

    /// The source for the current directory with no flags: what the configuration commands read.
    static var here: ConfigurationSource {
        ConfigurationSource(workingDirectory: FileManager.default.currentDirectoryPath, flags: Flags())
    }

    /// Reads every layer and resolves the model, all or nothing.
    /// - Throws: a ``ConfigurationError`` or a ``ProviderSettingsError``, naming the file.
    func load() throws -> RunSettings {
        let result = try loader.load(
            model: flags.model, provider: flags.provider, maxTurns: flags.maxTurns, compactAt: flags.compactAt)
        let providers = try ProviderSettings.load(from: providersPath)
        let model = try providers.resolve(
            provider: result.configuration.provider.value, model: result.configuration.model.value,
            environment: environment,
            storedKeys: { () throws(CredentialFileError) in try CredentialFile.standard().loadKeys().mapValues(\.key) })
        return RunSettings(
            configuration: result.configuration, model: model, applied: result.applied, notices: result.notices)
    }
}
