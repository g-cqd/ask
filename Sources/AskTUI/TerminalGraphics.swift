internal import TerminalKitCodecs

/// Whether the terminal draws kitty graphics, so pictures show as pixels (roadmap 0208).
///
/// Asked once, with kitty's query (one pixel, `a=q`, which the terminal answers without keeping anything), and only where the
/// environment says the terminal may be kitty or Ghostty (the owner chose WezTerm too, which turned out not to draw the placeholders),
/// never through tmux or ssh: a
/// terminal that does not know the protocol may print the query as text (TerminalKit's `TerminalProbe` saw Terminal.app do it). The
/// answer arrives as input, an APC string that TerminalKit reads whole.
enum TerminalGraphics {
    /// What the terminal said.
    enum Answer: Equatable {
        case supported
        case unsupported
    }

    /// The query's image id: `ASK1`, so the answer is told from any other.
    static let queryID: UInt32 = 0x4153_4B31

    /// The query: a 1×1 RGB pixel, sent directly, asked about and not kept.
    static func query() -> [UInt8] {
        GraphicsEncoder.encode(
            GraphicsCommand(
                action: .query,
                format: .rgb,
                transmission: .direct,
                id: queryID,
                width: 1,
                height: 1,
                payload: [0, 0, 0]
            )
        )
    }

    /// The terminal's answer in `bytes`: supported for `OK`, unsupported for an error; nil for anything that is not the answer.
    static func answer(to bytes: [UInt8]) -> Answer? {
        let text = String(decoding: bytes, as: UTF8.self)
        guard text.hasPrefix("\u{1B}_G"), let body = text.split(separator: ";", maxSplits: 1).last,
            text.contains("i=\(queryID);")
        else { return nil }
        return body.hasPrefix("OK") ? .supported : .unsupported
    }

    /// Whether the terminal may draw them, from what it says it is: kitty (`TERM=xterm-kitty`) or Ghostty (`TERM=xterm-ghostty` or
    /// `TERM_PROGRAM=ghostty`); not through tmux or over ssh, where graphics need passthrough.
    static func mayDraw(environment: [String: String]) -> Bool {
        if environment["TMUX"] != nil || environment["SSH_TTY"] != nil || environment["SSH_CONNECTION"] != nil {
            return false
        }
        let term = environment["TERM"] ?? ""
        let program = environment["TERM_PROGRAM"] ?? ""
        // Not WezTerm: it takes kitty graphics but not the Unicode placeholders ask draws with (seen 2026-11-06: the cells shown as
        // glyphs, the picture drawn at the cursor over the input).
        return term == "xterm-kitty" || term == "xterm-ghostty" || program == "ghostty"
    }
}
