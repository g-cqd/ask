public import Foundation

/// The provider and model one run uses, resolved from the command line and `providers.json`.
public struct ResolvedModel: Sendable, Equatable {
    /// Where requests go.
    public enum Provider: Sendable, Equatable {
        /// The built-in Anthropic provider, with ask's own sign-in.
        case anthropic
        /// The ChatGPT subscription's Codex backend, with ask's own Codex sign-in.
        case codex
        /// A server speaking OpenAI chat completions, at `baseURL`.
        case openAICompatible(name: String, baseURL: URL, apiKey: String?, headers: [String: String])
        /// A server speaking the Responses API, at `baseURL`.
        case openAIResponses(name: String, baseURL: URL, apiKey: String?, headers: [String: String])
    }

    public let provider: Provider
    public let model: String
    /// A named subscription registration; nil retains the legacy default provider behavior.
    public var connection: ConnectionRecord?
    /// The alias the user typed, when the model came from one; `model` is then the server's id.
    public var alias: String?
    /// The model's context window in tokens, when the settings say.
    public var contextWindow: Int?
    /// The longest reply the model allows, when the settings say.
    // @dl:accept -- two plain value types that hold the same optional limits share a shape, not behaviour; a base type would only be a name for it
    public var maxOutputTokens: Int?

    /// A resolved provider and model, with what is known of the model's limits.
    public init(provider: Provider, model: String, contextWindow: Int? = nil, maxOutputTokens: Int? = nil) {
        self.provider = provider
        self.model = model
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
    }
}
