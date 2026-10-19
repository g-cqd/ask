public import Foundation

/// Streams responses from any server that speaks OpenAI chat completions: llama.cpp, MLX, Ollama, vLLM, LM Studio,
/// hosted gateways and OpenAI itself.
///
/// The servers agree on the request and differ in the stream, and ``OpenAIStreamDecoder`` absorbs the differences
/// measured on three of them (diary 11). No compatibility switch exists for a difference nobody has observed.
public struct OpenAICompatibleClient: Sendable {
    private let endpoint: ProviderEndpoint

    /// A client for the server at `baseURL`.
    /// - Parameters:
    ///   - transport: what sends the requests.
    ///   - baseURL: the server's API root, the URL that ends in `/v1` on most servers.
    ///   - apiKey: sent as a bearer token; local servers usually need none.
    ///   - headers: extra headers a gateway asks for.
    public init(transport: any HTTPTransport, baseURL: URL, apiKey: String? = nil, headers: [String: String] = [:]) {
        endpoint = ProviderEndpoint(
            transport: transport, baseURL: baseURL, path: "chat/completions", apiKey: apiKey, headers: headers)
    }

    /// Sends `request` and streams the response's events. The stream throws an ``OpenAICompatibleError``.
    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        endpoint.stream(OpenAIRequestEncoder.encode(request), decoder: OpenAIStreamDecoder.self)
    }
}
