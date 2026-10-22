public import AskAI
internal import Synchronization

/// A provider whose thinking control needs a lookup that must not delay startup. The lookup runs just before the
/// first request that needs it, and its result is kept; a failed lookup is not kept, so the next request tries again.
/// A failure ends that request without contacting the provider: the user's setting is never quietly dropped.
///
/// The loop makes one request at a time. Two concurrent first requests would each look the control up, which costs
/// a repeated read and cannot produce a different answer from the same metadata.
public final class DeferredThinkingProvider: ModelProvider {
    private enum Lookup {
        case pending
        case done(ThinkingControl?)
    }

    private let inner: any ModelProvider
    private let resolve: @Sendable () async throws -> ThinkingControl?
    private let lookup = Mutex(Lookup.pending)

    /// - Parameters:
    ///   - inner: the provider every resolved request is sent to.
    ///   - resolve: chooses the control. It may use the network, and runs outside the terminal's input path.
    public init(inner: any ModelProvider, resolve: @escaping @Sendable () async throws -> ThinkingControl?) {
        self.inner = inner
        self.resolve = resolve
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, any Error> {
        ModelStream.after { [self] in
            var resolved = request
            resolved.thinking = try await control()
            return inner.stream(resolved)
        }
    }

    private func control() async throws -> ThinkingControl? {
        if case .done(let control) = lookup.withLock({ $0 }) { return control }
        let control = try await resolve()
        lookup.withLock { $0 = .done(control) }
        return control
    }
}
