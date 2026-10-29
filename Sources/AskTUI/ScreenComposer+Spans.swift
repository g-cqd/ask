internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The row's text cut into runs, each with the style it is drawn in: the line's own, an accent over it, and the selection as inverse
    /// over both (nothing else is painted by a selection). Each link is given an OSC 8 id from where it starts on screen, `row` and its
    /// column, so two occurrences of one URI are two links to the terminal and hovering one does not light up the other.
    static func spans(of line: Line, highlight: Range<Int>?, row: Int = 0) -> [(String, Style)] {
        let width = UnicodeWidth.displayWidth(of: line.text)
        var cuts: Set<Int> = [0, width]
        for accent in line.accents { cuts.formUnion([accent.columns.lowerBound, accent.columns.upperBound]) }
        for link in line.links { cuts.formUnion([link.columns.lowerBound, link.columns.upperBound]) }
        if let highlight { cuts.formUnion([highlight.lowerBound, highlight.upperBound]) }
        let edges = cuts.filter { $0 >= 0 && $0 <= width }.sorted()
        var spans: [(String, Style)] = []
        for (low, high) in zip(edges, edges.dropFirst()) {
            let part = ColumnSlicer.split(line.text, columns: low ..< high).selected
            guard !part.isEmpty else { continue }
            var style = line.accents.first { $0.columns.contains(low) }?.style ?? line.style
            if line.style.bg != .default, style.bg == .default { style.bg = line.style.bg }
            if let link = line.links.first(where: { $0.columns.contains(low) }) {
                style.link = link.uri
                style.linkID = "ask-\(row)-\(link.columns.lowerBound)"
            }
            if let highlight, highlight.contains(low) { style.inverse = true }
            spans.append((part, style))
        }
        return spans
    }
}
