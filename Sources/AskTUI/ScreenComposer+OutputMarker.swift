internal import TerminalKitStyle
internal import TerminalKitText

/// The row between a long output's head and tail (roadmap 0078): dim like the other folds' placeholders, owned by the block so a
/// click reaches it, and with no source, so a selection across it copies the two ends and not the marker.
extension ScreenComposer {
    static func withOutputMarker(
        _ rows: [Line], _ output: ShownToolOutput, before line: Int, block: Int, columns: Int, style: BlockStyle
    ) -> [Line] {
        let width = Swift.max(1, columns - 2 * style.inset)
        let text = ColumnSlicer.split(output.marker, columns: 0 ..< width).selected
        var marker = Line(text: String(repeating: " ", count: style.inset) + text, style: Style(dim: true))
        marker.foldBlock = block
        marker.foldsMiddle = true
        let sourced = rows.indices.filter { rows[$0].source?.block == block }
        let at =
            sourced.first { rows[$0].source.map { $0.line >= line } ?? false }
            ?? sourced.last.map { $0 + 1 } ?? rows.endIndex
        var result = rows
        result.insert(marker, at: at)
        return result
    }
}
