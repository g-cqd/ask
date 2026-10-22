internal import Synchronization

/// The sandbox the model narrowed the whole session to, if it did (roadmap 0019). Every call runs under the run's
/// policy intersected with it, so it can only narrow and never reaches past the run, even after a configuration
/// reload. It holds the effective policy, not the last request: narrowing one dimension later keeps the others.
public final class SessionNarrowing: Sendable {
    private let state = Mutex<SandboxPolicy?>(nil)

    /// None yet.
    public init() {}

    /// The narrowed policy, or nil for the run's own.
    public var policy: SandboxPolicy? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}
