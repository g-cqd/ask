/// How a hook behaves when it exceeds its deadline (roadmap 0192, ADR-0143).
public enum HookFailureMode: String, Sendable, Equatable, Codable {
    /// Past the deadline, proceed as if the hook allowed or did nothing.
    case open
    /// Past the deadline, block or refuse with a timeout reason.
    case closed
}
