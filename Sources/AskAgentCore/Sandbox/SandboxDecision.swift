/// The answer to "may this happen?": yes, or no with the capability that refused and why, in words for the person. The model is
/// told only that it was not permitted (ADR-0115), so the reason is for a log, a test and the user's own screen.
public enum SandboxDecision: Sendable, Equatable {
    case allowed
    case denied(SandboxCapability, String)

    public var isAllowed: Bool { self == .allowed }
}
