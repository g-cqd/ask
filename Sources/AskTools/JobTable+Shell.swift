public import AskAgentCore
internal import Foundation

extension JobTable {
    /// What to tell the person when the configured `environment.shell` cannot be used, so the fallback is never silent; nil when
    /// none is configured or it is usable.
    /// - Parameters:
    ///   - policy: the run's command policy, which carries the configured shell.
    ///   - environment: the environment commands inherit, for its PATH and SHELL.
    /// - Returns: the notice, naming the shell that is used instead.
    public static func unusableShellNotice(_ policy: CommandEnvironment, environment: [String: String]) -> String? {
        guard let name = policy.shell, chosenShell(name, path: policy.filtered(environment)["PATH"]) == nil else {
            return nil
        }
        var fallback = policy
        fallback.shell = nil
        let used = JobTable(environment: environment).commandShell(nil, policy: fallback)
        let why = name.hasPrefix("/") ? "it is not an executable shell listed in /etc/shells" : "it is not on the PATH"
        return "environment.shell \"\(name)\" is not used: \(why). Commands run in \(used)."
    }
}
