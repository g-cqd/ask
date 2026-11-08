/// Where the session's colour shows (`ui.sessionTint`): the status line, the input's box, both, or neither.
public enum ScreenSessionTint: String, Sendable, Equatable {
    case both, status, input, none

    /// Whether the status line takes the session's colour behind it.
    var status: Bool { self == .both || self == .status }
    /// Whether the input's box is drawn in the session's colour.
    var input: Bool { self == .both || self == .input }
}
