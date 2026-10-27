internal import AskAI
internal import Foundation

/// The provider ask uses when nothing names one: the first one that can answer now, so a person signed in to Codex alone is not sent to
/// a Claude sign-in they never made (ADR-0117).
enum AutoProvider {
    /// What can answer, in order: Claude, Codex, Antigravity, then Apple's on-device model, which is the answer when nothing is signed in.
    ///
    /// A Claude credential in the environment decides at once, without opening the credential file, so a launch that already knew its
    /// provider pays nothing. Apple's model is chosen by name and not asked whether it is available: asking loads the framework's model
    /// stack, which measured 6.3 MB of the idle memory of every launch with no account (ADR-0116). If it cannot answer, the first
    /// request says why and how to sign in instead.
    static func pick(environment: [String: String]) -> String {
        if AnthropicEnvironmentAuth.variables.contains(where: { !(environment[$0] ?? "").isEmpty }) {
            return ProviderSettings.anthropic
        }
        let accounts =
            (try? CredentialFile.standard(environment: environment).signedInAccounts(environment: environment)) ?? []
        for name in [ProviderSettings.anthropic, ProviderSettings.codex, ProviderSettings.agy, CopilotProtocol.name]
        where accounts.contains(where: { $0.provider == name }) {
            return name
        }
        return ProviderSettings.apple
    }
}
