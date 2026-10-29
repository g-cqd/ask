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
    /// Sandboxed mode while a turn runs: the terminal's own text colour, in bold. ANSI white (7) was that colour only on a dark page and
    /// nearly vanished on a light one (roadmap 0108).
    static let sandboxed = Style(bold: true)

    /// The idle mark with the sandbox on: green, as a check mark is (roadmap 0133).
    static let protected = Style(fg: .indexed(2), bold: true)

    /// While compacting: the spinner and the word, in purple (roadmap 0099).
    static let compacting = Style(fg: .indexed(5))

    /// The mark while the conversation is compacted: `<spinner> Compacting...`.
    static func compactingMark(frame: String) -> StatusLeadingMark {
        StatusLeadingMark(character: frame + " Compacting...", style: compacting)
    }

    /// The mark while ask waits to reconnect: `<spinner> Reconnecting...`, in the warning colour.
    static func reconnectingMark(frame: String) -> StatusLeadingMark {
        StatusLeadingMark(character: frame + " Reconnecting...", style: warning)
    }

    /// The idle mark (roadmap 0133): a green check with the sandbox on, `!` in the warning colour with it off; `named` writes the word
    /// instead, `sandboxed` or `not sandboxed`, as a click on the mark shows it for a few seconds.
    static func idle(sandboxed: Bool, named: Bool = false) -> StatusLeadingMark {
        switch (sandboxed, named) {
            case (true, false): StatusLeadingMark(character: "✓", style: protected)
            case (true, true): StatusLeadingMark(character: "sandboxed", style: protected)
            case (false, false): StatusLeadingMark(character: "!", style: warning)
            case (false, true): StatusLeadingMark(character: "not sandboxed", style: warning)
        }
    }

    /// Evaluates the leading mark and style based on activity and sandbox state.
    static func mark(running: Bool, sandboxed: Bool, frame: String, named: Bool = false) -> StatusLeadingMark {
        guard running else { return idle(sandboxed: sandboxed, named: named) }
        let style = sandboxed ? Self.sandboxed : Self.warning
        return StatusLeadingMark(character: frame, style: style)
    }
}
