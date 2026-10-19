public import Foundation

/// The provider and model one run uses, resolved from the command line and `providers.json`.
public struct ResolvedModel: Sendable, Equatable {
    /// Where requests go.
    public enum Provider: Sendable, Equatable {
        /// The built-in Anthropic provider, with ask's own sign-in.
        case anthropic
        /// A server speaking OpenAI chat completions, at `baseURL`.
        case openAICompatible(name: String, baseURL: URL, apiKey: String?, headers: [String: String])
    }

    public let provider: Provider
    public let model: String
}
