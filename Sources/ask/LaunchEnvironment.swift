internal import AskAI
internal import AskAgentCore
internal import AskCore

/// The environment ask was launched with, and the one place that blanks what ask has read from it (ADR-0113).
///
/// Everything in `Sources/ask` reads `values`, never `ProcessInfo`, because the process's own copy loses its credentials once they are
/// concealed. `values` is taken before the first concealment: `conceal` touches it first.
enum LaunchEnvironment {
    /// The environment as ask was started, whatever has been blanked since.
    static let values = ProcessEnvironment.snapshot()

    /// Blanks, in ask's own process, every variable `policy` withholds from commands, so a command cannot read it from there either.
    /// - Parameter policy: the run's policy; its pass-through list is ignored, because ask itself has no use for a value after reading it.
    static func conceal(_ policy: CommandEnvironment) {
        _ = values
        // A throwaway keychain for tests and probes is named by an ASK_ variable, blanked below (roadmap 0110).
        _ = KeychainSecretStore.launchKeychainPath
        ProcessEnvironment.conceal { name in
            policy.withheld.contains(name) || policy.withheldPrefixes.contains { name.hasPrefix($0) }
        }
    }
}
