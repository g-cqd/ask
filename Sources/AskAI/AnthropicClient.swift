internal import AemiJSON
public import Foundation

/// Why an Anthropic request failed. Each case calls for a different response.
public enum AnthropicClientError: Error, Sendable, Equatable {
    /// The API answered with a non-2xx status, and its reason when the body carried one.
    case status(Int, ProviderFailure?)
    /// The event stream reported a failure, or broke the protocol.
    case stream(AnthropicStreamError)
    /// The event stream exceeded a size limit.
    case framing(SSEError)
    /// The connection closed in the middle of an event.
    case truncated
    /// The request did not complete.
    case transport(String)
}

/// Streams Anthropic Messages responses as ``ModelEvent``s.
public struct AnthropicClient: Sendable {
    /// How a request authenticates.
    public enum Auth: Sendable, Equatable {
        /// A Claude subscription access token (`sk-ant-oat…`).
        case subscription(accessToken: String)
        case apiKey(String)
    }

    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// The betas an OAuth access token needs. Headers do not affect the subscription gate (pi-integrations'
    /// bisection), so ask identifies itself honestly rather than as another client.
    public static let oauthBetas = "claude-code-20250219,oauth-2025-04-20"

    private let transport: any HTTPTransport
    private let endpoint: URL

    /// A client that sends through `transport` to `endpoint`.
    public init(transport: any HTTPTransport, endpoint: URL = AnthropicClient.endpoint) {
        self.transport = transport
        self.endpoint = endpoint
    }

    /// The Messages endpoint under `ANTHROPIC_BASE_URL` (as the official SDK reads it), else the default.
    public static func endpoint(environment: [String: String]) -> URL {
        guard let base = environment["ANTHROPIC_BASE_URL"], !base.isEmpty,
            let url = URL(string: base.hasSuffix("/") ? String(base.dropLast()) : base), url.scheme != nil
        else { return endpoint }
        return url.appending(path: "v1/messages")
    }

    /// Sends `request` and streams the response's events. The stream throws an ``AnthropicClientError``.
    public func stream(_ request: ModelRequest, auth: Auth) -> AsyncThrowingStream<ModelEvent, any Error> {
        let http = HTTPRequest(
            url: endpoint, method: "POST", headers: Self.headers(for: auth),
            body: AnthropicRequestEncoder.encode(request))
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

    static func headers(for auth: Auth) -> [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = [
            ("anthropic-version", "2023-06-01"), ("content-type", "application/json"), ("accept", "application/json"),
            ("user-agent", "ask")
        ]
        switch auth {
            case .subscription(let token):
                headers += [("authorization", "Bearer \(token)"), ("anthropic-beta", oauthBetas)]
            case .apiKey(let key):
                headers.append(("x-api-key", key))
        }
        return headers
    }

    private static func run(
        _ http: HTTPRequest, over transport: any HTTPTransport, yield: (ModelEvent) -> Void
    ) async throws {
        let response: HTTPStreamingResponse
        do {
            response = try await transport.send(http)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw AnthropicClientError.transport(String(describing: error))
        }
        guard response.status == 200 else {
            let body = (try? await response.collect(limit: 64 << 10)) ?? []
            throw AnthropicClientError.status(response.status, failure(in: body))
        }
        var framer = SSEDecoder()
        let decoder = AnthropicStreamDecoder()
        var frames: [SSEEvent] = []
        var events: [ModelEvent] = []
        for try await chunk in response.body {
            do { try framer.feed(chunk.span, into: &frames) } catch { throw AnthropicClientError.framing(error) }
            for frame in frames {
                do { try decoder.decode(frame, into: &events) } catch { throw AnthropicClientError.stream(error) }
            }
            frames.removeAll(keepingCapacity: true)
            for event in events { yield(event) }
            events.removeAll(keepingCapacity: true)
        }
        guard framer.finish() == .complete else { throw AnthropicClientError.truncated }
    }

    /// The provider's reason in an error body (`{"type":"error","error":{…}}`), if it has one.
    private static func failure(in body: [UInt8]) -> ProviderFailure? {
        var events: [ModelEvent] = []
        do {
            try AnthropicStreamDecoder().decode(SSEEvent(name: "error", data: body), into: &events)
        } catch .provider(let failure) {
            return failure
        } catch {
            return nil
        }
        return nil
    }
}
