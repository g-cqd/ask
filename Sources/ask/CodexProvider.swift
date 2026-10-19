internal import AskAI
internal import AskAgentCore
internal import Foundation

/// Adapts the Codex backend to the loop, taking the credentials per request so a long run survives a refresh.
struct CodexProvider: ModelProvider {
    let access: CodexAccess
    let transport: URLSessionTransport
    /// One identifier for this run, shared by its requests so the server can cache the prompt between them.
    let session: String

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (access, transport, session) = (access, transport, session)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let credentials = try await access.credentials(now: Date().timeIntervalSince1970)
                    let client = ResponsesClient.codex(transport: transport, credentials: credentials, session: session)
                    for try await event in client.stream(request) { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
