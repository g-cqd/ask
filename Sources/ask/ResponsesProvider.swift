internal import AskAI
internal import AskAgentCore

/// Adapts a Responses client to the loop. The client already streams neutral events; this only binds them.
struct ResponsesProvider: ModelProvider {
    let client: ResponsesClient

    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> { client.stream(request) }
}
