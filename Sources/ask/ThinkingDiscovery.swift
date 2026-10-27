internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Resolve capabilities only when an explicit nondefault policy needs them. Provider control selection is in AskAI;
/// this adapter supplies the selected connection's metadata and says what is known, not what inference will accept.
/// Loading never uses the network: a native Claude model with no cached descriptor is looked up just before its first
/// request (``lookup(_:model:environment:maximumTokens:)``), because a startup round trip would delay the first frame.
enum ThinkingDiscovery {
    struct Result {
        var model: ResolvedModel
        var control: ThinkingControl?
        var status: String
        var notices: [String]
        /// The control still has to be looked up before the first request.
        var pending = false
    }

    static func resolve(_ level: ThinkingLevel, model: ResolvedModel, environment: [String: String]) throws -> Result {
        if level == .providerDefault {
            return Result(model: model, control: nil, status: "provider defaults; no control sent", notices: [])
        }
        let (descriptor, notices) = cachedMetadata(model, environment: environment)
        if model.provider == .anthropic, descriptor == nil {
            return Result(
                model: model, control: nil, status: "will be looked up before the first request", notices: notices,
                pending: true)
        }
        let chosen = withNativeLimits(model, descriptor: descriptor)
        let maximum = ContextBudget(
            contextWindow: chosen.contextWindow, maxOutputTokens: chosen.maxOutputTokens, requestedCompactAt: nil
        )
        .maximumTokens
        let control = try ThinkingControl.select(level, model: chosen, descriptor: descriptor, maximumTokens: maximum)
        let known = model.provider == .anthropic || descriptor?.reasoningLevels.isEmpty == false
        let policy = control.map(String.init(describing:)) ?? "no control needed"
        let status =
            known ? "catalog-selected: \(policy); server may still refuse" : "requested: \(policy); support unverified"
        return Result(model: chosen, control: control, status: status, notices: notices)
    }

    /// The control for a native model with no cached descriptor: asks Anthropic for the list, which also fills the cache.
    /// - Parameters:
    ///   - level: the user's requested level.
    ///   - model: the selected native model and connection.
    ///   - environment: where credentials and the endpoint are read.
    ///   - maximumTokens: the request's output ceiling, which a legacy token budget must leave room within.
    /// - Returns: the control, or nil when the model needs none.
    /// - Throws: a catalog or authorization error, or a ``ThinkingError`` when the model lacks the level.
    static func lookup(
        _ level: ThinkingLevel, model: ResolvedModel, environment: [String: String], maximumTokens: Int
    ) async throws -> ThinkingControl? {
        let catalog = AnthropicModelDiscovery.catalog(environment: environment, connection: model.connection)
        let snapshot = try await catalog.models(now: Date().timeIntervalSince1970)
        return try ThinkingControl.select(
            level, model: model, descriptor: snapshot.models.first { $0.id == model.model },
            maximumTokens: maximumTokens)
    }

    /// The model's catalog entry: the cached one, else one downloaded now. For a list the person is looking at, which may wait; a run's start
    /// never does (``resolve(_:model:environment:)`` reads the cache only).
    static func descriptor(for model: ResolvedModel, environment: [String: String]) async -> CatalogModel? {
        if let cached = cachedMetadata(model, environment: environment).0 { return cached }
        let now = Date().timeIntervalSince1970
        let snapshot: CatalogSnapshot?
        switch model.provider {
            case .anthropic:
                snapshot =
                    try? await AnthropicModelDiscovery.catalog(environment: environment, connection: model.connection)
                    .models(now: now)
            case .codex:
                snapshot = try? await ModelDiscovery.codex(environment: environment, connection: model.connection)
                    .models(now: now)
            case .openAIResponses:
                snapshot = try? await ProviderModelDiscovery.catalog(for: model, environment: environment)?
                    .models(now: now)
            case .copilot:
                snapshot = (try? await ModelDiscovery.copilot(environment: environment).models(now: now))
                    .map { CatalogSnapshot(models: $0) }
            case .openAICompatible, .agy, .apple: snapshot = nil
        }
        return snapshot?.models.first { $0.id == model.model }
    }

    private static func cachedMetadata(_ model: ResolvedModel, environment: [String: String]) -> (
        CatalogModel?, [String]
    ) {
        let now = Date().timeIntervalSince1970
        do {
            switch model.provider {
                case .anthropic:
                    return (
                        try AnthropicModelDiscovery.catalog(environment: environment, connection: model.connection)
                            .cachedModel(model.model, now: now), []
                    )
                case .codex:
                    let snapshot = try ModelDiscovery.codex(environment: environment, connection: model.connection)
                        .cached(now: now)
                    return (snapshot?.models.first { $0.id == model.model }, [])
                case .openAIResponses:
                    return (
                        try ProviderModelDiscovery.catalog(for: model, environment: environment)?
                            .cachedModel(model.model, now: now), []
                    )
                case .copilot:
                    return (
                        try ModelDiscovery.copilot(environment: environment).cached(now: now)?
                            .first { $0.id == model.model }, []
                    )
                case .openAICompatible, .agy, .apple: return (nil, [])
            }
        } catch { return (nil, ["Thinking catalog not used: \(error)"]) }
    }

    /// An explicit native policy already paid for metadata. Retain the user's alias limits field by field; a newly
    /// learned output maximum may lower, but never raise, the existing reply budget. Unset/default runs do none of this.
    private static func withNativeLimits(_ model: ResolvedModel, descriptor: CatalogModel?) -> ResolvedModel {
        guard model.provider == .anthropic, let descriptor else { return model }
        var chosen = model
        chosen.contextWindow = model.contextWindow ?? descriptor.contextWindow
        if model.maxOutputTokens == nil, let maximum = descriptor.maxOutputTokens {
            chosen.maxOutputTokens = min(maximum, ContextBudget.defaultMaximumTokens)
        }
        return chosen
    }
}
