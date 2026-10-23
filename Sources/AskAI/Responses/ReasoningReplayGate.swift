internal import Synchronization

/// Remembers, for one run, that the server refused reasoning this client replayed, so later requests stop sending it
/// instead of failing and retrying every step. One gate belongs to one provider instance; a new run starts open.
public final class ReasoningReplayGate: Sendable {
    private let open = Mutex(true)

    /// A gate that allows replay.
    public init() {}

    /// Whether reasoning may still be sent.
    public var isOpen: Bool { open.withLock { $0 } }

    /// Stops replay for the rest of the run.
    public func close() { open.withLock { $0 = false } }
}
