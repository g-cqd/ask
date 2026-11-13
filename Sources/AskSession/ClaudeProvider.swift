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
        return ModelStream.after {
            let auth = try await auth()
            return client.stream(request, auth: auth)
        }
    }
}
