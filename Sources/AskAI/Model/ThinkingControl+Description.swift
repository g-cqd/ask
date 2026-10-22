extension ThinkingControl: CustomStringConvertible {
    /// The concrete request policy, not a claim that an inference server has accepted it.
    public var description: String {
        switch self {
            case .disabled: "off"
            case .betweenTools: "between-tools (no pre-response thinking)"
            case .effort(let level): "effort \(level.rawValue)"
            case .budget(let tokens, let effort):
                "budget \(tokens) tokens" + (effort.map { ", effort \($0.rawValue)" } ?? "")
        }
    }
}
