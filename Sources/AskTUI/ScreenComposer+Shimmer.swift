internal import TerminalKitStyle
internal import TerminalKitText

/// A running block's header shimmers (roadmaps 0171 and 0187): the header drawn fainter than dim, and a stretch along it drawn
/// bold in the text's own colour with a column of the page's secondary colour on each side, so it reads as a glow with soft edges rather
/// than a box. Its place comes from the time the block has run, at ``shimmerSpeed`` columns a second, redrawn every 60 ms while it runs.
extension ScreenComposer {
    /// The bold core of the stretch, in columns.
    static let shimmerCore = 4
    /// The whole stretch: the core and an edge on each side.
    static let shimmerWidth = shimmerCore + 2
    /// Columns a second.
    static let shimmerSpeed = 20

    /// The leftmost column of the stretch after `elapsed`, relative to the header's text, `-shimmerWidth` when it enters.
    static func shimmerStart(after elapsed: Duration, span: Int) -> Int {
        let milliseconds =
            Int(elapsed.components.seconds) * 1_000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return (milliseconds * shimmerSpeed / 1_000) % (span + shimmerWidth) - shimmerWidth
    }

    /// `rows` with the header row of `block`, its hard line 0, shimmering `elapsed` into the block. A header with accents of its own is
    /// left as it is.
    static func shimmering(_ rows: [Line], block: Int, elapsed: Duration, theme: ScreenTheme) -> [Line] {
        guard let row = rows.firstIndex(where: { $0.source?.block == block && $0.source?.line == 0 }),
            let source = rows[row].source, rows[row].accents.isEmpty
        else { return rows }
        let span = UnicodeWidth.displayWidth(of: source.text)
        guard span > 0 else { return rows }
        let start = shimmerStart(after: elapsed, span: span)
        var rows = rows
        let original = rows[row].style
        // Still dim, as a running header reads; its colour moved toward the page on top of that, so it is fainter than dim alone.
        var base = original
        base.dim = true
        base.fg = theme.shimmerBase
        var edge = original
        edge.dim = false
        edge.fg = theme.shimmerEdge
        var core = original
        core.dim = false
        core.bold = true
        rows[row].style = base
        let parts = [
            (start, start + 1, edge), (start + 1, start + 1 + shimmerCore, core),
            (start + 1 + shimmerCore, start + shimmerWidth, edge)
        ]
        rows[row].accents = parts.compactMap { low, high, style in
            let low = Swift.max(0, low)
            let high = Swift.min(span, high)
            return high > low ? Accent(columns: source.col + low ..< source.col + high, style: style) : nil
        }
        return rows
    }
}
