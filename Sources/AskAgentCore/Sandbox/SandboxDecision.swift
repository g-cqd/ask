/// The answer to "may this happen?": yes, or no with the capability that refused and why, in words the model
/// reads and can relay to the user.
public enum SandboxDecision: Sendable, Equatable {
    case allowed
    case denied(SandboxCapability, String)

    public var isAllowed: Bool { self == .allowed }
}
