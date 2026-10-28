internal import AskAI
internal import AskAgentCore
internal import Foundation

/// The `ui.onlyUsefulModels` setting as the model lists read it (roadmap 0089).
enum ModelFilter {
    /// Whether lists leave out the models of no use to ask: the setting in the effective configuration, on when it is not set or the
    /// configuration cannot be read (the run reports that problem itself).
    static func onlyUseful(environment: [String: String] = LaunchEnvironment.values) -> Bool {
        let loader = ConfigurationLoader(
            project: FileManager.default.currentDirectoryPath,
            configDirectory: askConfigDirectory(environment: environment),
            environment: environment)
        return (try? loader.load().configuration.ui.value.onlyUsefulModels) ?? true
    }
}
