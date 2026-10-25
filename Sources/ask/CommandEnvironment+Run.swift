internal import AskAI
internal import AskAgentCore

extension CommandEnvironment {
    /// The policy for a run: the variables ask reads credentials from (providers, presets, `providers.json`, MCP servers), then what the
    /// configuration says (ADR-0106).
    init(providers: ProviderSettings, configuration: Configuration) {
        let mcp = configuration.mcp.value.servers.reduce(into: Set<String>()) { $0.formUnion($1.referencedVariables) }
        self.init(
            credentials: CredentialVariables.names(settings: providers).union(mcp),
            credentialPrefixes: CredentialVariables.prefixes, configured: configuration.environment.value)
    }
}
