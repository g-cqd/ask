/// A requested thinking policy cannot be represented honestly. The caller should change the setting, not retry it or
/// silently choose another level.
public enum ThinkingError: Error, Sendable, Equatable, CustomStringConvertible {
    case unavailable(model: String, level: ThinkingLevel, available: [String])
    case missingCapabilities(model: String)
    case unsupportedProtocol(String)
    case invalidControl(String)
    case insufficientOutput(minimum: Int, available: Int)

    public var description: String {
        switch self {
            case .unavailable(let model, let level, let available):
                "thinking \(level.rawValue) is unavailable for \(model); choose \(available.joined(separator: ", ")) or default"
            case .missingCapabilities(let model):
                "thinking controls for \(model) are unknown; refresh its model catalog, or use thinking default"
            case .unsupportedProtocol(let name):
                "explicit thinking controls are not implemented for \(name); use thinking default"
            case .invalidControl(let reason): "invalid thinking control: \(reason)"
            case .insufficientOutput(let minimum, let available):
                "thinking needs at least \(minimum) output tokens including room for an answer, but this request allows \(available)"
        }
    }
}
