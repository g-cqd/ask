internal import AskAI
internal import Foundation

/// The CLI's binding of an OpenAI-compatible provider's model list to ask's private config directory.
enum ProviderModelDiscovery {
    /// The catalog of the provider `listing` describes, kept in `models-NAME.json` beside the credentials.
    ///
    /// A provider name that is not a plain word (one a `providers.json` could hold, with a slash or a dot-dot) keeps no cache:
    /// the name would become part of a path.
    static func catalog(
        for listing: ProviderSettings.Listing, environment: [String: String]
    ) -> ProviderModelCatalog {
        ProviderModelCatalog(
            name: listing.name, baseURL: listing.baseURL, apiKey: listing.apiKey, headers: listing.headers,
            cache: cache(named: listing.name, environment: environment), transport: URLSessionTransport())
    }

    /// The catalog of the provider a resolved model goes to, or nil for a provider with its own catalog.
    static func catalog(for resolved: ResolvedModel, environment: [String: String]) -> ProviderModelCatalog? {
        switch resolved.provider {
            case .anthropic, .codex, .agy, .apple: nil
            case .openAICompatible(let name, let baseURL, let apiKey, let headers),
                .openAIResponses(let name, let baseURL, let apiKey, let headers):
                catalog(
                    for: ProviderSettings.Listing(name: name, baseURL: baseURL, apiKey: apiKey, headers: headers),
                    environment: environment)
        }
    }

    private static func cache(named name: String, environment: [String: String]) -> ModelCatalogFile? {
        guard (1 ... 64).contains(name.utf8.count),
            name.utf8.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D })
        else { return nil }
        return ModelCatalogFile(
            url: URL(fileURLWithPath: askConfigDirectory(environment: environment) + "/models-\(name).json"))
    }
}
