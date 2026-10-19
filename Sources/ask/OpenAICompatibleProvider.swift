internal import AskAI
internal import AskAgentCore

/// Adapts an OpenAI-compatible client to the loop. The client already streams neutral events; this only binds them.
struct OpenAICompatibleProvider: ModelProvider {
    let client: OpenAICompatibleClient

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> { client.stream(request) }
}
