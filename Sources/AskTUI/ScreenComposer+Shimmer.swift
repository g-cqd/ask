internal import TerminalKitStyle
internal import TerminalKitText

/// A running block's header shimmers (roadmap 0171, `ui.shimmer`): a stretch of it drawn brighter moves along it, two columns a spinner
/// tick, so the effect costs no timer of its own and stops with the spinner.
extension ScreenComposer {
    /// The columns the brighter stretch covers.
    static let shimmerWidth = 4

    /// `rows` with the header row of `block`, its hard line 0, shimmering at animation frame `frame`. A header with accents of its own
    /// is left as it is.
    static func shimmering(_ rows: [Line], block: Int, frame: Int) -> [Line] {
        guard let row = rows.firstIndex(where: { $0.source?.block == block && $0.source?.line == 0 }),
            let source = rows[row].source, rows[row].accents.isEmpty
        else { return rows }
        let span = UnicodeWidth.displayWidth(of: source.text)
        guard span > 0 else { return rows }
        // The stretch enters from the left, crosses the header, and leaves on the right before it starts again.
        let start = (frame * 2) % (span + shimmerWidth) - shimmerWidth
        let low = Swift.max(0, start)
        let high = Swift.min(span, start + shimmerWidth)
        guard high > low else { return rows }
        var rows = rows
        var bright = rows[row].style
        if bright.dim { bright.dim = false } else { bright.bold = true }
        rows[row].accents = [Accent(columns: source.col + low ..< source.col + high, style: bright)]
        return rows
    }
}
