public import Foundation

/// Streams responses from any server that speaks the Responses API: OpenAI, the ChatGPT subscription's backend, and
/// llama.cpp.
///
/// Everything but the protocol is shared with the chat-completions client (``ProviderStream``): framing, error
/// statuses, retry advice and delivery. ``ResponsesStreamDecoder`` is the only part that knows this protocol.
public struct ResponsesClient: Sendable {
    private let endpoint: ProviderEndpoint
    private let dialect: ResponsesDialect
    private let replay: ReasoningReplayGate?

    /// A client for the server at `baseURL`.
    /// - Parameters:
    ///   - transport: what sends the requests.
    ///   - baseURL: the API root; requests go to `responses` beneath it.
    ///   - apiKey: sent as a bearer token; local servers usually need none.
    ///   - headers: extra headers the server asks for.
    ///   - dialect: how this server's requests differ from the plain API's.
    ///   - replay: remembers a refusal of replayed reasoning for the run; nil retries each time it is refused.
    public init(
        transport: any HTTPTransport, baseURL: URL, apiKey: String? = nil, headers: [String: String] = [:],
        dialect: ResponsesDialect = .standard, replay: ReasoningReplayGate? = nil
    ) {
        endpoint = ProviderEndpoint(
            transport: transport, baseURL: baseURL, path: "responses", apiKey: apiKey, headers: headers)
        self.dialect = dialect
        self.replay = replay
    }

    /// Sends `request` and streams the response's events. The stream throws an ``OpenAICompatibleError``.
    ///
    /// When the request replays reasoning and the server refuses it as unverifiable before any event, the request is sent
    /// once more without that reasoning, the person is told, and later requests of the run skip replay.
    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        if let problem = request.thinking?.responsesProblem { return problem.failedStream }
        let replaying =
            dialect.replaysReasoning && replay?.isOpen != false
            && ResponsesRequestEncoder.carriesReplayableReasoning(request)
        var sent = dialect
        sent.replaysReasoning = replaying
        let first = endpoint.stream(
            ResponsesRequestEncoder.encode(request, dialect: sent), decoder: ResponsesStreamDecoder.self)
        guard replaying else { return first }
        var withoutReplay = dialect
        withoutReplay.replaysReasoning = false
        let plain = withoutReplay
        let (endpoint, gate) = (endpoint, replay)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var delivered = false
                do {
                    for try await event in first {
                        delivered = true
                        continuation.yield(event)
                    }
                    continuation.finish()
                    return
                } catch let error as OpenAICompatibleError where !delivered && error.rejectsReplayedReasoning {
                    gate?.close()
                    continuation.yield(
                        .notice(
                            "The server could not verify the reasoning ask sent back, so this run continues without it."
                        ))
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                do {
                    let body = ResponsesRequestEncoder.encode(request, dialect: plain)
                    for try await event in endpoint.stream(body, decoder: ResponsesStreamDecoder.self) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
