internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Adapts the Codex backend to the loop, taking the credentials per request so a long run survives a refresh.
struct CodexProvider: ModelProvider {
    let access: CodexAccess
    let transport: URLSessionTransport
    /// One identifier for this run, shared by its requests so the server can cache the prompt between them.
    let session: String
    /// Remembers for this run that the server refused replayed reasoning, so it is not sent again.
    let replay = ReasoningReplayGate()

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (access, transport, session, replay) = (access, transport, session, replay)
        return ModelStream.after {
            let credentials = try await access.credentials(now: Date().timeIntervalSince1970)
            let client = ResponsesClient.codex(
                transport: transport, credentials: credentials, session: session, replay: replay)
            return client.stream(request)
        }
    }
}
