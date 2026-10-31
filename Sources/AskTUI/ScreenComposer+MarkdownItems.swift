internal import TerminalKitStyle
internal import TerminalKitText

/// Markdown beyond replies (roadmap 0151): the model's reasoning and the person's messages go through the same renderer as replies, each
/// keeping its look over every mark (reasoning dim and italic, the person's message bold). Copy takes what was written, through the rows'
/// segments, as it does for replies.
extension ScreenComposer {
    /// The rows of item `index` drawn as Markdown, or nil when the item is not drawn as Markdown (Markdown off, another kind, folded
    /// or empty reasoning).
    static func markdownItemLines(in transcript: Transcript, at index: Int, columns: Int, style: BlockStyle) -> [Line]?
    {
        guard transcript.markdown else { return nil }
        switch transcript.items[index] {
            case .user(let text):
                let rows = styled(
                    markdownLines(text, in: transcript, at: index, columns: columns, style: style),
                    under: Style(bold: true))
                // The older look set the user's message off with a blank row above it; the padded one has a row of padding for that.
                return (style.padded ? [] : [Line(text: "", style: .default)]) + rows
            case .thinking(let text):
                let kept = Transcript.kept(text)
                guard !transcript.isFolded(index), Transcript.saysSomething(kept) else { return nil }
                let look = Style(dim: true, italic: true)
                var rows =
                    thinkingHeaderRow(
                        kept, folded: false, progress: transcript.progress[index], block: index,
                        width: Swift.max(1, columns - 2 * style.inset), style: style)
                    + styled(
                        markdownLines(kept, in: transcript, at: index, columns: columns, style: style), under: look)
                for row in rows.indices { rows[row].foldBlock = index }
                return rows
            default:
                return nil
        }
    }

    /// `rows` with `look` as the row style and under every accent, so a mark adds to the item's look instead of replacing it.
    private static func styled(_ rows: [Line], under look: Style) -> [Line] {
        rows.map { row in
            var row = row
            row.style = merged(row.style, under: look)
            for accent in row.accents.indices {
                row.accents[accent].style = merged(row.accents[accent].style, under: look)
            }
            return row
        }
    }

    private static func merged(_ style: Style, under look: Style) -> Style {
        var style = style
        if look.bold { style.bold = true }
        if look.dim { style.dim = true }
        if look.italic { style.italic = true }
        return style
    }
}
