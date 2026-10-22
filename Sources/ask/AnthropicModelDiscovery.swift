internal import AskAI
internal import Foundation

/// Binds native discovery to the same endpoint and credential owner as Messages. This factory itself performs no reads.
enum AnthropicModelDiscovery {
    static func catalog(
        environment: [String: String], connection: ConnectionRecord? = nil
    ) -> AnthropicModelCatalog {
        let file = NamedConnections.file(for: connection, environment: environment)
        let transport = URLSessionTransport()
        let owner = AnthropicAuthorization(file: file, connection: connection, transport: transport)
        let endpoint = AnthropicClient.endpoint(environment: connection == nil ? environment : [:])
            .deletingLastPathComponent().appending(path: "models")
        return AnthropicModelCatalog(
            endpoint: endpoint,
            cache: ModelCatalogFile(url: file.url.deletingLastPathComponent().appending(path: "models-anthropic.json")),
            transport: transport, connectionID: connection?.id,
            authorize: { now in try await owner.auth(environment: environment, now: now) },
            cachedAuthorization: { now in try owner.cached(environment: environment, now: now) })
    }
}
