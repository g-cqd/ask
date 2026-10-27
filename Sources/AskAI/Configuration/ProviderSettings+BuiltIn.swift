extension ProviderSettings {
    /// Built-in names cannot be redefined by file configuration.
    func builtIn(_ name: String, model: String?, catalog: [CatalogModel]) throws(ProviderSettingsError)
        -> ResolvedModel?
    {
        for reserved in [Self.anthropic, Self.codex, Self.agy, Self.apple, CopilotProtocol.name]
        where entries[reserved] != nil {
            throw .reservedName(reserved)
        }
        switch name {
            case Self.anthropic: return ResolvedModel(provider: .anthropic, model: model ?? Self.anthropicDefaultModel)
            case Self.codex, CopilotProtocol.name:
                guard let chosen = model ?? catalog.first?.id else { throw .noModel(provider: name) }
                return Self.resolved(name == Self.codex ? .codex : .copilot, chosen, from: catalog)
            case Self.agy:
                guard let chosen = model else { throw .noModel(provider: name) }
                return Self.resolved(.agy, chosen, from: catalog)
            case Self.apple: return Self.resolved(.apple, model ?? Self.appleModel, from: catalog)
            default: return nil
        }
    }

    private static func resolved(_ provider: ResolvedModel.Provider, _ chosen: String, from catalog: [CatalogModel])
        -> ResolvedModel
    {
        let listed = catalog.first { $0.id == chosen }
        return ResolvedModel(
            provider: provider, model: chosen, contextWindow: listed?.contextWindow,
            maxOutputTokens: listed?.maxOutputTokens)
    }
}
