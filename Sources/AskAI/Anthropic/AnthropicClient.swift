internal import AemiJSON
public import Foundation

/// Streams Anthropic Messages responses as ``ModelEvent``s.
public struct AnthropicClient: Sendable {
    /// How a request authenticates.
    public enum Auth: Sendable, Equatable {
        /// A Claude subscription access token (`sk-ant-oat…`).
        case subscription(accessToken: String)
        /// A plain bearer token, as a gateway in front of the API expects (`ANTHROPIC_AUTH_TOKEN`): `Authorization: Bearer`
        /// and nothing that identifies a subscription.
        case bearer(String)
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

    private static func baseURL(_ environment: [String: String]) -> BaseURL {
        guard let base = environment["ANTHROPIC_BASE_URL"], !base.isEmpty else { return .unset }
        guard let url = URL(string: base.hasSuffix("/") ? String(base.dropLast()) : base) else {
            return .refused("it is not a URL")
        }
        if let reason = EndpointPolicy.refusal(for: url, carriesCredential: true) { return .refused(reason) }
        return .use(url)
    }

    /// Sends `request` and streams the response's events. The stream throws an ``AnthropicClientError``.
    public func stream(_ request: ModelRequest, auth: Auth) -> AsyncThrowingStream<ModelEvent, any Error> {
        if let problem = request.thinking?.anthropicProblem(maximumTokens: request.maxTokens) {
            return problem.failedStream
        }
        let http = HTTPRequest(
            url: endpoint, method: "POST", headers: Self.headers(for: auth),
            body: AnthropicRequestEncoder.encode(request))
        return ProviderStream.events(
            http, over: transport, decoder: AnthropicStreamDecoder.self, succeeds: { $0 == 200 })
    }

    static func headers(for auth: Auth) -> [(name: String, value: String)] {
        var headers: [(name: String, value: String)] = [
            ("anthropic-version", "2023-06-01"), ("content-type", "application/json"), ("accept", "application/json"),
            ("user-agent", "ask")
        ]
        switch auth {
            case .subscription(let token):
                headers += [("authorization", "Bearer \(token)"), ("anthropic-beta", oauthBetas)]
            case .bearer(let token): headers.append(("authorization", "Bearer \(token)"))
            case .apiKey(let key):
                headers.append(("x-api-key", key))
        }
        return headers
    }
}
