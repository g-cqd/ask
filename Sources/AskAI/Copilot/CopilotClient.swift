internal import Foundation

/// Dispatches only models from this account's catalog. No policy enablement, protocol guessing or automatic 401 replay.
public struct CopilotClient: Sendable {
    private let catalog: CopilotCatalog
    private let transport: any HTTPTransport
    private let session = UUID().uuidString
    public init(file: CredentialFile, transport: any HTTPTransport) {
        catalog = CopilotCatalog(file: file, transport: transport)
        self.transport = transport
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        .producing { yield in
            let now = Date().timeIntervalSince1970
            let models = try await catalog.models(now: now)
            guard let model = models.first(where: { $0.id == request.model }), let path = model.api else {
                throw SignInError.invalidResponse(
                    "Model is not in the Copilot account catalog; refresh with ask models copilot-vscode")
            }
            let credential = try await catalog.access.credentials(now: now)
            let url = try CopilotProtocol.endpoint(credential.apiURL).appending(path: String(path.dropFirst()))
            let last = request.messages.last
            let userInitiated =
                last?.role == .user
                && last?.blocks
                    .contains(where: {
                        if case .text = $0 { return true }
                        return false
                    }) == true
            var headers = CopilotProtocol.headers(credential, session: session)
            headers += [
                ("openai-intent", "conversation-agent"), ("x-initiator", userInitiated ? "user" : "agent")
            ]
            if path == "/responses", let problem = request.thinking?.responsesProblem { throw problem }
            if path == "/v1/messages",
                let problem = request.thinking?.anthropicProblem(maximumTokens: request.maxTokens)
            {
                throw problem
            }
            if path == "/chat/completions", request.thinking != nil {
                throw ThinkingError.unsupportedProtocol("OpenAI chat completions")
            }
            let body: [UInt8]
            switch path {
                case "/responses": body = ResponsesRequestEncoder.encode(request, dialect: .standard)
                case "/v1/messages": body = AnthropicRequestEncoder.encode(request)
                default: body = OpenAIRequestEncoder.encode(request)
            }
            let http = HTTPRequest(url: url, method: "POST", headers: headers, body: body, allowsRedirects: false)
            let guarded = CopilotTransport(inner: transport, url: url)
            switch path {
                case "/responses":
                    for try await event in ProviderStream.events(
                        http, over: guarded, decoder: ResponsesStreamDecoder.self, succeeds: { $0 == 200 })
                    { yield(event) }
                case "/v1/messages":
                    var http = http
                    http.headers.append(("anthropic-version", "2023-06-01"))
                    for try await event in ProviderStream.events(
                        http, over: guarded, decoder: AnthropicStreamDecoder.self, succeeds: { $0 == 200 })
                    { yield(event) }
                default:
                    for try await event in ProviderStream.events(
                        http, over: guarded, decoder: OpenAIStreamDecoder.self, succeeds: { $0 == 200 })
                    { yield(event) }
            }
        }
    }
}
