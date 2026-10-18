/// Why the model stopped generating.
public enum StopReason: Sendable, Equatable {
    case endTurn, maxTokens, stopSequence, toolUse, pauseTurn, refusal, contextWindowExceeded
    /// A reason this decoder does not know, kept verbatim.
    case other(String)
}

extension StopReason {
    private static let names: [(StopReason, String)] = [
        (.endTurn, "end_turn"), (.maxTokens, "max_tokens"), (.stopSequence, "stop_sequence"), (.toolUse, "tool_use"),
        (.pauseTurn, "pause_turn"), (.refusal, "refusal"), (.contextWindowExceeded, "model_context_window_exceeded")
    ]

    /// The reason for its name on the wire; an unknown name is kept verbatim.
    public init(wire: String) {
        self = Self.names.first { $0.1 == wire }?.0 ?? .other(wire)
    }

    /// The reason's name on the wire, which sessions persist.
    public var wire: String {
        if case .other(let name) = self { return name }
        return Self.names.first { $0.0 == self }?.1 ?? ""
    }
}
