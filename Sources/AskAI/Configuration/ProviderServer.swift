public import Foundation

/// Where a model's requests go (roadmap 0021): what the `provider` network level lets commands reach through ask's proxy.
public enum ProviderServer {
    /// The server `model`'s requests are sent to; nil for a model that runs on the device.
    /// - Parameters:
    ///   - model: the run's model and provider.
    ///   - environment: where Anthropic's base URL may be set, for a model without a named connection.
    /// - Returns: the server's address.
    public static func url(for model: ResolvedModel, environment: [String: String]) -> URL? {
        switch model.provider {
            case .anthropic: AnthropicClient.endpoint(environment: model.connection == nil ? environment : [:])
            case .codex: URL(string: "https://chatgpt.com")
            case .copilot: URL(string: CopilotProtocol.defaultAPI)
            case .agy: AgyCloud.baseURL
            case .apple: nil
            case .openAICompatible(_, let baseURL, _, _), .openAIResponses(_, let baseURL, _, _): baseURL
        }
    }
}
