public import Foundation

/// Streams responses from any server that speaks the Responses API: OpenAI, the ChatGPT subscription's backend, and
/// llama.cpp.
///
/// Everything but the protocol is shared with the chat-completions client (``ProviderStream``): framing, error
/// statuses, retry advice and delivery. ``ResponsesStreamDecoder`` is the only part that knows this protocol.
public struct ResponsesClient: Sendable {
    private let endpoint: ProviderEndpoint
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
        endpoint = ProviderEndpoint(
            transport: transport, baseURL: baseURL, path: "responses", apiKey: apiKey, headers: headers)
        self.sendsOutputLimit = sendsOutputLimit
    }

    /// Sends `request` and streams the response's events. The stream throws an ``OpenAICompatibleError``.
    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        endpoint.stream(
            ResponsesRequestEncoder.encode(request, sendsOutputLimit: sendsOutputLimit),
            decoder: ResponsesStreamDecoder.self)
    }
}
