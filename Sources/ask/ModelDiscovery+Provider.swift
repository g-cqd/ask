internal import AskAI
internal import Foundation

extension ModelDiscovery {
    /// The provider to use when nothing named one (not a flag, the configuration or providers.json's default): one that can answer now. Said
    /// once, so a run never silently goes somewhere the person did not choose.
    static func automatic(
        _ provider: String?, providers: ProviderSettings, environment: [String: String]
    ) -> (provider: String?, notices: [String]) {
        guard provider == nil, !providers.namesDefault else { return (provider, []) }
        let picked = AutoProvider.pick(environment: environment)
        switch picked {
            case ProviderSettings.anthropic: return (picked, [])
            case ProviderSettings.apple:
                return (
                    picked, ["Nothing is signed in: using Apple's on-device model. /login signs in, /model switches."]
                )
            default:
                return (
                    picked,
                    ["No provider chosen; using \(picked), which you are signed in to. /model switches."]
                )
        }
    }
}
