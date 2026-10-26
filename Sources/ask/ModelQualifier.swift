internal import AskAI
internal import AskApple
internal import Foundation

/// Which provider serves a model nobody qualified, and which names count as providers when one is (ADR-0118).
///
/// Inference reads only what is cached on disk: a model id is looked for in the list of every account signed in to, and a launch never waits for
/// a network to choose. When the thinking effort is also given, a provider whose entry for the model does not take that effort is passed over.
enum ModelQualifier {
    /// Every name that can start `provider/model`.
    static func providerNames(_ providers: ProviderSettings, environment: [String: String]) -> Set<String> {
        var names: Set<String> = [
            ProviderSettings.anthropic, ProviderSettings.codex, ProviderSettings.agy, ProviderSettings.apple
        ]
        names.formUnion(ProviderPreset.names)
        names.formUnion(providers.configuredNames)
        names.formUnion(Array((try? CredentialFile.standard(environment: environment).loadKeys().keys) ?? [:].keys))
        names.formUnion(((try? NamedConnections.registry(environment: environment).list().records) ?? []).map(\.name))
        return names
    }

    /// The provider whose cached list holds `model`, the first by preference when several do; nil when none does.
    static func infer(
        model: String, thinking: ThinkingLevel, providers: ProviderSettings, environment: [String: String]
    ) -> String? {
        if model == ProviderSettings.appleModel { return ProviderSettings.apple }
        let file = CredentialFile.standard(environment: environment)
        let accounts = (try? file.signedInAccounts(environment: environment)) ?? []
        let now = Date().timeIntervalSince1970
        var found: [(provider: String, entry: CatalogModel?, kind: ResolvedModel.Provider)] = []
        func has(_ name: String) -> Bool { accounts.contains { $0.provider == name } }
        if has(ProviderSettings.anthropic),
            let entry = try? AnthropicModelDiscovery.catalog(environment: environment).cachedModel(model, now: now)
        {
            found.append((ProviderSettings.anthropic, entry, .anthropic))
        }
        if has(ProviderSettings.codex),
            let entry = (try? ModelDiscovery.codex(environment: environment).cached(now: now))?.models
                .first(where: { $0.id == model })
        {
            found.append((ProviderSettings.codex, entry, .codex))
        }
        if has(ProviderSettings.agy),
            (try? ModelDiscovery.agy(environment: environment).cachedModel(model, now: now)) != nil
        {
            found.append((ProviderSettings.agy, nil, .agy))
        }
        let storedKeys: () throws(CredentialFileError) -> [String: String] = { try file.loadKeys().mapValues(\.key) }
        for name in Set(accounts.map(\.provider)).union(providers.configuredNames).sorted()
        where ![ProviderSettings.anthropic, ProviderSettings.codex, ProviderSettings.agy].contains(name) {
            guard
                let listing = try? providers.listing(provider: name, environment: environment, storedKeys: storedKeys),
                let entry = try? ProviderModelDiscovery.catalog(for: listing, environment: environment)
                    .cachedModel(model, now: now)
            else { continue }
            found.append(
                (name, entry, .openAIResponses(name: name, baseURL: listing.baseURL, apiKey: nil, headers: [:])))
        }
        let fits = found.filter { candidate in
            thinking == .providerDefault
                || ThinkingOptions.choices(for: candidate.kind, descriptor: candidate.entry)?.levels.contains(thinking)
                    == true
        }
        // A model the effort rules out everywhere is still the model asked for: the effort is refused later, with its reason.
        return (fits.first ?? found.first)?.provider
            ?? (model.hasPrefix("claude") && has(ProviderSettings.anthropic) ? ProviderSettings.anthropic : nil)
    }
}
