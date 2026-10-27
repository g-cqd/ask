internal import TerminalKitStyle
internal import TerminalKitText

/// Leading visual indicator for the status line (spinner or idle fallback mark) and its color style.
struct StatusLeadingMark: Sendable, Equatable {
    var character: String
    var style: Style?

    init(character: String, style: Style? = nil) {
        self.character = character
        self.style = style
    }

    /// Yellow accent style for unsandboxed mode or warnings.
    static let warning = Style(fg: .indexed(3))
    /// White/bold-white style for sandboxed mode.
    static let sandboxed = Style(fg: .indexed(7))

    /// Evaluates the leading mark and style based on activity and sandbox state.
    static func mark(running: Bool, sandboxed: Bool, frame: String) -> StatusLeadingMark {
        guard running else {
            return StatusLeadingMark(character: "!", style: sandboxed ? Self.sandboxed : Self.warning)
        }
        let style = sandboxed ? Self.sandboxed : Self.warning
        return StatusLeadingMark(character: frame, style: style)
    }
}
