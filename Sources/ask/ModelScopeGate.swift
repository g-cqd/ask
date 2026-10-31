internal import AskAgentCore
internal import Foundation

/// The `modelScopes` rule for the project ask runs in (roadmap 0094, ADR-0137): what `/model`, `ask models` and the choice of a model
/// read. No rules means no git file is read.
enum ModelScopeGate {
    /// The rule `configuration` holds for `project`, nil when none matches.
    static func match(_ configuration: Configuration, project: String, environment: [String: String])
        -> ModelScopeMatch?
    {
        guard !configuration.modelScopes.value.isEmpty else { return nil }
        return configuration.modelScope(for: RepositoryFacts.read(project: project, environment: environment))
    }

    /// The rule for the current folder, read from the effective configuration; nil when the configuration cannot be read (the run
    /// reports that problem itself, and refuses there).
    static func current(environment: [String: String] = LaunchEnvironment.values) -> ModelScopeMatch? {
        let project = FileManager.default.currentDirectoryPath
        let loader = ConfigurationLoader(
            project: project, configDirectory: askConfigDirectory(environment: environment), environment: environment)
        guard let configuration = try? loader.load().configuration else { return nil }
        return match(configuration, project: project, environment: environment)
    }
}
