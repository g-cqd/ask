internal import AemiJSON
public import Foundation

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

    /// Why `ANTHROPIC_BASE_URL` is being ignored, or nil when it is unset, empty or in use. Never echoes the value,
    /// which may carry credentials of its own.
    public static func endpointProblem(environment: [String: String]) -> String? {
        if case .refused(let reason) = baseURL(environment) { return "ANTHROPIC_BASE_URL was ignored: \(reason)." }
        return nil
    }

    /// The Messages endpoint under `ANTHROPIC_BASE_URL` (as the official SDK reads it), else the default.
    ///
    /// Every request carries a bearer credential, so the variable is honoured only for `https`, or for plain
    /// `http` to this machine. Anything else is ignored and the official endpoint used: the safe direction, since
    /// the credential then goes only where it was issued. ``endpointProblem(environment:)`` says why.
    public static func endpoint(environment: [String: String]) -> URL {
        guard case .use(let url) = baseURL(environment) else { return endpoint }
        return url.appending(path: "v1/messages")
    }

    private enum BaseURL {
        case unset
        case use(URL)
        case refused(String)
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    private static func baseURL(_ environment: [String: String]) -> BaseURL {
        guard let base = environment["ANTHROPIC_BASE_URL"], !base.isEmpty else { return .unset }
        guard let url = URL(string: base.hasSuffix("/") ? String(base.dropLast()) : base),
            let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false)?.lowercased()
        else { return .refused("it is not a URL") }
        switch scheme {
            case "https": return .use(url)
            case "http" where loopbackHosts.contains(host): return .use(url)
            case "http":
                return .refused(
                    "plain http to another machine would send the credential unencrypted; use https, or http only for localhost"
                )
            default: return .refused("it is not an http or https URL")
        }
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
            // `retry-after` in seconds; the HTTP-date form is not used by this API and is ignored.
            let retryAfter = response.headers["retry-after"].flatMap(Double.init).flatMap { $0 >= 0 ? $0 : nil }
            throw AnthropicClientError.status(response.status, failure(in: body), retryAfter: retryAfter)
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
