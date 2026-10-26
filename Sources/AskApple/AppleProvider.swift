public import AskAI
public import AskAgentCore

/// Answers from Apple's on-device model, in this process (ADR-0116): no network, no account, no key, no cost.
///
/// Each request is a fresh session over the conversation ask keeps, because ask's session file is the one history. A tool the model calls
/// is handed back to the loop, which runs it under the sandbox, as for any other provider.
public struct AppleProvider: ModelProvider {
    /// A provider. It offers every tool the loop has, as every other provider does (ADR-0120).
    public init() {}

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await AppleRun(request: request).run { continuation.yield($0) }
                    continuation.finish()
                } catch { continuation.finish(throwing: AppleFailure.mapped(error)) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
