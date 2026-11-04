/// Why ask is waiting on the person, for the `waiting` hook point (roadmap 0192, ADR-0143).
public enum HookWaitingReason: Sendable, Equatable {
    case approval(tool: String)
    case question(count: Int)
    case runEnded
}
