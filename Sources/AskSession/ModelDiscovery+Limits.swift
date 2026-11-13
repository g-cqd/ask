internal import AskAI
internal import AskAgentCore
internal import AskApple
internal import Foundation

// Each provider's window and reply limits for the model just resolved; apart from ModelDiscovery.swift to keep
// each file under the 250-line ceiling and the type body under 200 lines.
extension ModelDiscovery {
    static func withAppleLimits(_ initial: ResolvedModel, notices: [String]) -> (
        model: ResolvedModel, notices: [String]
    ) {
        var chosen = initial
        chosen.contextWindow = AppleModel.fallbackContextWindow
        chosen.maxOutputTokens = AppleModel.maximumOutputTokens
        return (chosen, notices)
    }

    /// The named connection `selected` names, if it names one: the built-in providers never do, and anything else is looked up in the registry.
    static func registered(_ selected: String, environment: [String: String]) throws -> (
        ConnectionRecord?, [String]
    ) {
        let builtIn = [ProviderSettings.anthropic, ProviderSettings.codex, ProviderSettings.agy, ProviderSettings.apple]
        guard !builtIn.contains(selected) else { return (nil, []) }
        let listing = try NamedConnections.registry(environment: environment).list()
        return (listing.records.first { $0.name == selected.lowercased() }, listing.notices)
    }

    /// An explicit Codex model can use the account's cached limits without discovering or changing its choice.
    static func withCodexLimits(
        _ initial: ResolvedModel,
        environment: [String: String],
        resolve: ([CatalogModel]) throws -> ResolvedModel,
        notices: [String]
    ) -> (model: ResolvedModel, notices: [String]) {
        do {
            guard
                let cached = try codex(environment: environment, connection: initial.connection)
                    .cached(now: Date().timeIntervalSince1970)
            else {
                return (initial, notices + announcement(initial))
            }
            let chosen = try resolve(cached.models)
            return (chosen, notices + cached.notices + announcement(chosen))
        } catch { return (initial, notices + ["Model catalog not used for the explicit model: \(error)"]) }
    }

    /// The run's model with the limits its provider's cached list states, when there is a fresh one. Never a network: the list is
    /// fetched by `ask models NAME`, and a run that has none simply knows no window until the provider's refusal says one. Only
    /// the run's own model is decoded: the list can hold hundreds, and decoding them all cost 2 ms of the start (diary 57).
    static func withListedLimits(
        _ initial: ResolvedModel,
        environment: [String: String],
        resolve: ([CatalogModel]) throws -> ResolvedModel,
        notices: [String]
    ) throws -> (model: ResolvedModel, notices: [String]) {
        let listed: CatalogModel?
        do {
            listed = try ProviderModelDiscovery.catalog(for: initial, environment: environment)?
                .cachedModel(initial.model, now: Date().timeIntervalSince1970)
        } catch { return (initial, notices + ["Model list not used: \(error)"] + announcement(initial)) }
        guard let listed else { return (initial, notices + announcement(initial)) }
        let chosen = try resolve([listed])
        return (chosen, notices + announcement(chosen))
    }

    /// The Claude model with the window and reply limit the cached `v1/models` list states, when there is a fresh one for the current
    /// sign-in. Never a network and no refresh: one small file, and only this model's entry decoded. Without it the status line showed
    /// `?` and the context budget had no window unless a thinking level was set (roadmap 0147).
    static func withAnthropicLimits(
        _ initial: ResolvedModel,
        environment: [String: String],
        notices: [String]
    ) -> (model: ResolvedModel, notices: [String]) {
        let listed: CatalogModel?
        do {
            listed = try AnthropicModelDiscovery.catalog(environment: environment, connection: initial.connection)
                .cachedModel(initial.model, now: Date().timeIntervalSince1970)
        } catch { return (initial, notices + ["Model list not used: \(error)"] + announcement(initial)) }
        let chosen = ThinkingDiscovery.withNativeLimits(initial, descriptor: listed)
        return (chosen, notices + announcement(chosen))
    }

    /// The Antigravity model with the limits the cached list states for it, when there is a fresh one. Never a network, and only the
    /// run's own entry is decoded, as for `withListedLimits`.
    static func withAgyLimits(
        _ initial: ResolvedModel,
        resolve: ([CatalogModel]) throws -> ResolvedModel,
        notices: [String]
    ) throws -> (model: ResolvedModel, notices: [String]) {
        let listed: CatalogModel?
        do { listed = try agy().cachedModel(initial.model, now: Date().timeIntervalSince1970) } catch {
            return (initial, notices + ["Model list not used: \(error)"])
        }
        guard let listed else { return (initial, notices) }
        return (try resolve([listed]), notices)
    }

    /// Says which server model an alias stood for, so a run never hides what it sent.
    static func announcement(_ resolved: ResolvedModel) -> [String] {
        guard let alias = resolved.alias, let connection = resolved.connection else { return [] }
        return [detail("Using \(connection.name)/\(alias), which is \(resolved.model).")]
    }
}
