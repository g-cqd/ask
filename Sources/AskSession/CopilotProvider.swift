internal import AskAI
internal import AskAgentCore

/// The experimental Copilot account's native protocol dispatch.
struct CopilotProvider: ModelProvider {
    let client: CopilotClient
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> { client.stream(request) }
}
