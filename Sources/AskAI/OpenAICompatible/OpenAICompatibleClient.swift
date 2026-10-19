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
        let transport = transport
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.run(http, over: transport) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(_ http: HTTPRequest, over transport: any HTTPTransport, yield: (ModelEvent) -> Void)
        async throws
    {
        let response = try await send(http, over: transport)
        guard (200 ... 299).contains(response.status) else { throw await rejection(response) }
        try await decode(response, yield: yield)
    }

    private static func send(_ http: HTTPRequest, over transport: any HTTPTransport) async throws
        -> HTTPStreamingResponse
    {
        do {
            return try await transport.send(http)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw OpenAICompatibleError.transport(String(describing: error))
        }
    }

    /// The error for a non-2xx response: its status, the reason its body gives, and any `retry-after` seconds.
    private static func rejection(_ response: HTTPStreamingResponse) async -> OpenAICompatibleError {
        let body = (try? await response.collect(limit: 64 << 10)) ?? []
        let retryAfter = response.headers["retry-after"].flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil }
        return .status(response.status, failure(in: body), retryAfter: retryAfter)
    }

    private static func decode(_ response: HTTPStreamingResponse, yield: (ModelEvent) -> Void) async throws {
        var framer = SSEDecoder()
        var decoder = OpenAIStreamDecoder()
        var frames: [SSEEvent] = []
        var events: [ModelEvent] = []
        for try await chunk in response.body {
            do { try framer.feed(chunk.span, into: &frames) } catch { throw OpenAICompatibleError.framing(error) }
            for frame in frames {
                do { try decoder.decode(frame, into: &events) } catch { throw OpenAICompatibleError.stream(error) }
            }
            frames.removeAll(keepingCapacity: true)
            for event in events { yield(event) }
            events.removeAll(keepingCapacity: true)
        }
        guard framer.finish() == .complete else { throw OpenAICompatibleError.truncated }
        do { try decoder.finish(into: &events) } catch { throw OpenAICompatibleError.stream(error) }
        for event in events { yield(event) }
    }

    /// The server's reason in an error body (`{"error":{…}}`), if it has one.
    private static func failure(in body: [UInt8]) -> ProviderFailure? {
        var decoder = OpenAIStreamDecoder()
        var events: [ModelEvent] = []
        do {
            try decoder.decode(SSEEvent(name: "message", data: body), into: &events)
        } catch .provider(let failure) {
            return failure
        } catch {
            return nil
        }
        return nil
    }
}
