public import Foundation

/// Streams responses from any server that speaks OpenAI chat completions: llama.cpp, MLX, Ollama, vLLM, LM Studio,
/// hosted gateways and OpenAI itself.
///
/// The servers agree on the request and differ in the stream, and ``OpenAIStreamDecoder`` absorbs the differences
/// measured on three of them (diary 11). No compatibility switch exists for a difference nobody has observed.
public struct OpenAICompatibleClient: Sendable {
    private let transport: any HTTPTransport
    private let endpoint: URL
    private let apiKey: String?
    private let headers: [String: String]

    /// A client for the server at `baseURL`.
    /// - Parameters:
    ///   - transport: what sends the requests.
    ///   - baseURL: the server's API root, the URL that ends in `/v1` on most servers.
    ///   - apiKey: sent as a bearer token; local servers usually need none.
    ///   - headers: extra headers a gateway asks for.
    public init(transport: any HTTPTransport, baseURL: URL, apiKey: String? = nil, headers: [String: String] = [:]) {
        self.transport = transport
        self.endpoint = baseURL.appending(path: "chat/completions")
        self.apiKey = apiKey
        self.headers = headers
    }

    /// Sends `request` and streams the response's events. The stream throws an ``OpenAICompatibleError``.
    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        var headers: [(name: String, value: String)] = [
            ("content-type", "application/json"), ("accept", "text/event-stream"), ("user-agent", "ask")
        ]
        if let apiKey, !apiKey.isEmpty { headers.append(("authorization", "Bearer \(apiKey)")) }
        headers += self.headers.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
        let http = HTTPRequest(
            url: endpoint, method: "POST", headers: headers, body: OpenAIRequestEncoder.encode(request))
        return ProviderStream.events(
            http, over: transport, decoder: OpenAIStreamDecoder.self, succeeds: { (200 ... 299).contains($0) })
    }
}
