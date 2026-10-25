/// The environment variables ask itself reads credentials from (ADR-0106): the names a command the model runs must not inherit by default.
///
/// ask knows these exactly, because it is what reads them, so withholding them costs a person nothing they did not already hand ask. A variable
/// of the person's own that ask does not read is the person's to withhold, through the `environment` section of the configuration.
public enum CredentialVariables {
    /// Prefixes of ask's own namespaces: `ANTHROPIC_` (a key, a token, and the address a key is sent to) and `ASK_` (ask's settings).
    public static let prefixes = ["ANTHROPIC_", "ASK_"]

    /// The exact names: the Anthropic ones, each preset's key variable, and every variable `providers.json` names for a key.
    /// - Parameter settings: the provider settings in force.
    /// - Returns: the names, never a value.
    public static func names(settings: ProviderSettings) -> Set<String> {
        Set(AnthropicEnvironmentAuth.variables).union(ProviderPreset.all.compactMap(\.keyVariable))
            .union(settings.referencedVariables)
    }
}
