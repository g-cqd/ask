/// A model as a person writes it: `gpt-6-sol`, or `codex/gpt-6-sol` to say which provider serves it (ADR-0118).
///
/// Only the part before the first slash can be a provider, and only when it names one that exists: a model id may contain slashes itself
/// (`org/model` on a router), and `openrouter/org/model` is that provider's `org/model`.
public struct ReferencedModel: Sendable, Equatable {
    public let provider: String?
    public let model: String

    /// Reads `raw` against the provider names that exist, compared without regard to case. `claude` is Anthropic.
    public init(_ raw: String, providers: Set<String>) {
        let lowered = Set(providers.map { $0.lowercased() })
        if let slash = raw.firstIndex(of: "/") {
            let prefix = raw[..<slash].lowercased()
            let rest = String(raw[raw.index(after: slash)...])
            if !rest.isEmpty, lowered.contains(prefix) || prefix == "claude" {
                provider = prefix == "claude" ? ProviderSettings.anthropic : prefix
                model = rest
                return
            }
        }
        provider = nil
        model = raw
    }
}
