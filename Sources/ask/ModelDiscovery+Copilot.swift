internal import AskAI
internal import Foundation

extension ModelDiscovery {
    static func resolveCopilot(
        _ providers: ProviderSettings, model: String?, environment: [String: String], allowNetwork: Bool,
        notices: [String]
    ) async throws -> (model: ResolvedModel, notices: [String]) {
        let catalog = copilot(environment: environment)
        let now = Date().timeIntervalSince1970
        let models =
            allowNetwork && model == nil ? try await catalog.models(now: now) : (try catalog.cached(now: now) ?? [])
        return (
            try providers.resolve(
                provider: CopilotProtocol.name, model: model, environment: environment, catalog: models), notices
        )
    }

    static func copilot(environment: [String: String]) -> CopilotCatalog {
        CopilotCatalog(file: .standard(environment: environment), transport: URLSessionTransport())
    }
}
