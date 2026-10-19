/// Why a loopback listener could not be started.
public enum LoopbackError: Error, Sendable, Equatable {
    /// The port could not be bound, with the system's error: usually it is in use, as when the Codex CLI is
    /// signing in at the same time. The caller falls back to a pasted address.
    case bindFailed(errno: Int32)
}
