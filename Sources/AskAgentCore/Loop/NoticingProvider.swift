public import AskAI

/// A provider that tells the person something its credentials layer knows, once per request, without touching the response (ADR-0091).
///
/// The notice is asked for after the first event, because that is when the request is under way and the credentials have been used,
/// and at the end of a stream that had none, so a request that fails right away still says it. A notice is not part of a response
/// (the assembler ignores it), so wrapping a provider changes what the person sees and nothing the model is sent or sends back.
public struct NoticingProvider<Base: ModelProvider>: ModelProvider {
    private let base: Base
    private let notice: @Sendable () -> String?

    /// Wraps `base`.
    /// - Parameters:
    ///   - base: the provider to wrap.
    ///   - notice: asked once per request, after it is under way; what it returns is shown to the person.
    public init(base: Base, notice: @escaping @Sendable () -> String?) {
        self.base = base
        self.notice = notice
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        let (base, notice) = (self.base, self.notice)
        return AsyncThrowingStream { continuation in
            let task = Task {
                var asked = false
                func ask() {
                    guard !asked else { return }
                    asked = true
                    if let text = notice() { continuation.yield(.notice(text)) }
                }
                do {
                    for try await event in base.stream(request) {
                        continuation.yield(event)
                        ask()
                    }
                    ask()
                    continuation.finish()
                } catch {
                    ask()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
