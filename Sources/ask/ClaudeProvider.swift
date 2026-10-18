internal import AemiJSON
internal import AskAI
internal import AskAgentCore
internal import AskTools
internal import Foundation

/// Adapts the Anthropic client to the loop, resolving auth per request so a long run survives a refresh.
struct ClaudeProvider: ModelProvider {
    let client: AnthropicClient
    let auth: @Sendable () async throws -> AnthropicClient.Auth

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (client, auth) = (client, auth)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in client.stream(request, auth: try await auth()) { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
