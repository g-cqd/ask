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
    /// Sandboxed mode: the terminal's own text colour, in bold. ANSI white (7) was that colour only on a dark page and nearly vanished on a
    /// light one (roadmap 0108).
    static let sandboxed = Style(bold: true)

    /// Evaluates the leading mark and style based on activity and sandbox state.
    static func mark(running: Bool, sandboxed: Bool, frame: String) -> StatusLeadingMark {
        guard running else {
            return StatusLeadingMark(character: "!", style: sandboxed ? Self.sandboxed : Self.warning)
        }
        let style = sandboxed ? Self.sandboxed : Self.warning
        return StatusLeadingMark(character: frame, style: style)
    }
}
