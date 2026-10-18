public import AskAI

/// Streams model responses. The composition root adapts a provider client to it; tests script it.
public protocol ModelProvider: Sendable {
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error>
}
