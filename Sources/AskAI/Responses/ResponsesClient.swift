public import Foundation

/// Streams responses from any server that speaks the Responses API: OpenAI, the ChatGPT subscription's backend, and
/// llama.cpp.
///
/// Everything but the protocol is shared with the chat-completions client (``ProviderStream``): framing, error
/// statuses, retry advice and delivery. ``ResponsesStreamDecoder`` is the only part that knows this protocol.
public struct ResponsesClient: Sendable {
    private let transport: any HTTPTransport
    private let endpoint: URL
    private let apiKey: String?
    private let headers: [String: String]
    private let sendsOutputLimit: Bool

    /// A client for the server at `baseURL`.
    /// - Parameters:
    ///   - transport: what sends the requests.
    ///   - baseURL: the API root; requests go to `responses` beneath it.
    ///   - apiKey: sent as a bearer token; local servers usually need none.
    ///   - headers: extra headers the server asks for.
    ///   - sendsOutputLimit: whether requests carry `max_output_tokens`, which the ChatGPT subscription's backend refuses.
    public init(
        transport: any HTTPTransport, baseURL: URL, apiKey: String? = nil, headers: [String: String] = [:],
        sendsOutputLimit: Bool = true
    ) {
        self.transport = transport
        self.endpoint = baseURL.appending(path: "responses")
        self.apiKey = apiKey
        self.headers = headers
        self.sendsOutputLimit = sendsOutputLimit
    }

    /// Sends `request` and streams the response's events. The stream throws an ``OpenAICompatibleError``.
    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        var headers: [(name: String, value: String)] = [
            ("content-type", "application/json"), ("accept", "text/event-stream"), ("user-agent", "ask")
        ]
        if let apiKey, !apiKey.isEmpty { headers.append(("authorization", "Bearer \(apiKey)")) }
        headers += self.headers.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
        let http = HTTPRequest(
            url: endpoint, method: "POST", headers: headers,
            body: ResponsesRequestEncoder.encode(request, sendsOutputLimit: sendsOutputLimit))
        return ProviderStream.events(
            http, over: transport, decoder: ResponsesStreamDecoder.self, succeeds: { (200 ... 299).contains($0) })
    }
}
