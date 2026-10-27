internal import AskAI
internal import AskApple
internal import AskTUI
internal import Foundation

/// Every model ask can reach right now, gathered from each provider the person is signed in to, for `/model `.
///
/// Each source is asked at once and given a few seconds: a provider that is slow or down is left out of the list and named at its end, and
/// never holds the others back. A fresh cache answers without a network.
enum ModelChoices {
    /// How long one provider has to answer.
    static let patience = Duration.seconds(8)

    /// One provider's list, under the name `/model` reaches it by.
    private struct Listing: Sendable {
        let provider: String
        let load: @Sendable () async throws -> [CatalogModel]
    }

    /// The rows, the current model's provider first.
    static func rows(current: ResolvedModel, environment: [String: String]) async -> [ChoiceRow] {
        let now = Date().timeIntervalSince1970
        let listings = Self.listings(environment: environment, now: now)
        let results = await withTaskGroup(of: (String, Result<[CatalogModel], any Error>).self) { group in
            for listing in listings {
                group.addTask { (listing.provider, await Deadline.run(patience) { try await listing.load() }) }
            }
            var all: [String: Result<[CatalogModel], any Error>] = [:]
            for await (provider, result) in group { all[provider] = result }
            return all
        }
        let currentName = current.connection?.name ?? current.providerName
        var ordered = listings.map(\.provider)
        if let index = ordered.firstIndex(of: currentName) { ordered.insert(ordered.remove(at: index), at: 0) }
        var rows: [ChoiceRow] = []
        var failed: [String] = []
        for provider in ordered {
            switch results[provider] {
                case .success(let models):
                    rows += models.map { offer($0, provider: provider, current: current, currentName: currentName) }
                case .failure(let error): failed.append("\(provider): \(error)")
                case nil: break
            }
        }
        if !failed.isEmpty {
            rows.append(
                ChoiceRow(
                    label: "· not listed", detail: failed.joined(separator: "; "), arguments: "", isCurrent: false))
        }
        return rows
    }

    private static func offer(_ model: CatalogModel, provider: String, current: ResolvedModel, currentName: String)
        -> ChoiceRow
    {
        var facts: [String] = []
        if provider == ProviderSettings.apple, let variant = AppleModel.variantName { facts.append(variant) }
        if let window = model.contextWindow { facts.append(window >= 1000 ? "\(window / 1000)k ctx" : "\(window) ctx") }
        if !model.reasoningLevels.isEmpty { facts.append("effort " + model.reasoningLevels.joined(separator: " ")) }
        return ChoiceRow(
            label: "\(provider)/\(model.id)", detail: facts.joined(separator: " · "),
            arguments: "\(provider) \(model.id)",
            isCurrent: provider == currentName && model.id == current.model)
    }

    /// The providers that can be listed: what is signed in, what providers.json names, Apple's model, and the named connections.
    private static func listings(environment: [String: String], now: Double) -> [Listing] {
        let file = CredentialFile.standard(environment: environment)
        let accounts = (try? file.signedInAccounts(environment: environment)) ?? []
        return signedIn(accounts, environment: environment, now: now)
            + keyed(accounts, file: file, environment: environment, now: now)
            + connections(environment: environment, now: now)
    }

    /// Claude, Codex, Antigravity and Apple's model, each when it is there to ask.
    private static func signedIn(_ accounts: [SignedInAccount], environment: [String: String], now: Double) -> [Listing]
    {
        var listings: [Listing] = []
        func has(_ provider: String) -> Bool { accounts.contains { $0.provider == provider } }
        if has(ProviderSettings.anthropic) {
            listings.append(
                Listing(provider: ProviderSettings.anthropic) {
                    try await AnthropicModelDiscovery.catalog(environment: environment).models(now: now).models
                })
        }
        if has(ProviderSettings.codex) {
            listings.append(
                Listing(provider: ProviderSettings.codex) {
                    try await ModelDiscovery.codex(environment: environment).models(now: now).models
                })
        }
        if has(ProviderSettings.agy) {
            listings.append(
                Listing(provider: ProviderSettings.agy) {
                    let agy = ModelDiscovery.agy(environment: environment)
                    if let cached = try agy.cached(now: now) { return cached.models }
                    return try await agy.refreshed(now: now).snapshot.models
                })
        }
        if has(CopilotProtocol.name) {
            listings.append(
                Listing(provider: CopilotProtocol.name) {
                    try await ModelDiscovery.copilot(environment: environment).models(now: now)
                })
        }
        if AppleModel.availability().isAvailable {
            listings.append(Listing(provider: ProviderSettings.apple) { [AppleModel.catalogEntry] })
        }
        return listings
    }

    /// Every provider reached with a key, stored or in the environment, and every one providers.json names.
    private static func keyed(
        _ accounts: [SignedInAccount], file: CredentialFile, environment: [String: String], now: Double
    ) -> [Listing] {
        let providers =
            (try? ProviderSettings.load(from: askConfigDirectory(environment: environment) + "/providers.json"))
            ?? .none
        let keyed = Set(accounts.map(\.provider))
            .subtracting([
                ProviderSettings.anthropic, ProviderSettings.codex, ProviderSettings.agy, CopilotProtocol.name
            ])
        return keyed.union(providers.configuredNames).sorted()
            .map { name in
                Listing(provider: name) {
                    guard
                        let listing = try providers.listing(
                            provider: name, environment: environment,
                            storedKeys: { () throws(CredentialFileError) in try file.loadKeys().mapValues(\.key) })
                    else { return [] }
                    return try await ProviderModelDiscovery.catalog(for: listing, environment: environment)
                        .models(now: now).models
                }
            }
    }

    /// The named connections, each its own account.
    private static func connections(environment: [String: String], now: Double) -> [Listing] {
        let records = (try? NamedConnections.registry(environment: environment).list().records) ?? []
        return records.map { record in
            Listing(provider: record.name) {
                switch record.provider {
                    case .codex:
                        try await ModelDiscovery.codex(environment: environment, connection: record).models(now: now)
                            .models
                    case .anthropic:
                        try await AnthropicModelDiscovery.catalog(environment: environment, connection: record)
                            .models(now: now).models
                }
            }
        }
    }
}
