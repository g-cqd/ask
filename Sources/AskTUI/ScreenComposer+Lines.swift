internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The rows an item is drawn as: its content, and with a padded style one row of padding around it (tinted to the edge when the kind has a tint),
    /// and a blank row above when this block and the one before are both tool calls or the user's messages.
    static func lines(
        for item: Transcript.Item, folded: Bool = false, block: Int = 0, columns: Int, style: BlockStyle = .plain,
        spacerAbove: Bool = false, progress: BlockProgress? = nil
    ) -> [Line] {
        let content = contentLines(
            for: item, folded: folded, block: block, columns: columns, style: style, progress: progress)
        var result = framed(content, kind: item, style: style, spacerAbove: spacerAbove)
        switch item {
            case .tool, .thinking:
                for index in result.indices where !(style.padded && spacerAbove && index == 0) {
                    result[index].foldBlock = block
                }
            default: break
        }
        return result
    }

    /// Wraps every block, including command and authentication notices, in padding, tint and spacing.
    static func framed(_ content: [Line], kind: Transcript.Item, style: BlockStyle, spacerAbove: Bool) -> [Line] {
        guard style.padded else { return content }
        let tint = style.theme.tint(for: kind)
        func tinted(_ line: Line) -> Line {
            var line = line
            line.style.bg = tint
            return line
        }
        let padding = Line(text: "", style: Style(bg: tint))
        return (spacerAbove ? [Line(text: "", style: .default)] : []) + [padding] + content.map(tinted) + [padding]
    }

    /// Whether the item is one of the kinds set apart by a blank row from a neighbour of the same sort.
    static func isSpaced(_ item: Transcript.Item) -> Bool {
        switch item {
            case .user, .tool: true
            default: false
        }
    }

    private static func contentLines(
        for item: Transcript.Item, folded: Bool, block: Int, columns: Int, style: BlockStyle, progress: BlockProgress?
    ) -> [Line] {
        let inset = style.inset
        let width = Swift.max(1, columns - 2 * inset)
        let margin = String(repeating: " ", count: inset)
        func rows(_ text: String, style: Style) -> [Line] {
            TextWrap.rows(text, width: width)
                .map { row in
                    Line(
                        text: margin + row.text, style: style,
                        source: Source(block: block, line: row.line, offset: row.offset, col: inset, text: row.text))
                }
        }
        switch item {
            case .user(let text):
                // The older look set the user's message off with a blank row above it; the padded one has a row of padding for that.
                return (style.padded ? [] : [Line(text: "", style: .default)]) + rows(text, style: Style(bold: true))
            case .assistant(let text):
                return rows(text, style: .default)
            case .tool(let name, let summary, let status, let output):
                let look: Style
                switch status {
                    case .running: look = Style(dim: true)
                    case .succeeded: look = Style(fg: .indexed(2), dim: true)
                    case .failed: look = Style(fg: .indexed(1))
                }
                let header = Transcript.Item.toolHeader(
                    name: name, summary: summary, status: status, output: output, folded: folded)
                let gap = style.padded && !folded && !output.isEmpty ? [Line(text: "", style: .default)] : []
                return blockHeader(
                    header,
                    metadata: blockMetadata(
                        status: status, output: output, progress: progress, localizedDurations: style.localizedDurations
                    ),
                    block: block, width: width, inset: inset, style: look) + gap
                    + (folded
                        ? [] : body(of: output, block: block, width: width, inset: inset, style: Style(dim: true)))
            case .thinking(let text):
                let kept = Transcript.kept(text)
                let look = Style(dim: true, italic: true)
                let header = Transcript.Item.thinkingHeader(body: kept, folded: folded)
                return blockHeader(
                    folded || kept.isEmpty ? header : kept,
                    metadata: blockMetadata(
                        status: progress?.ended == nil && progress != nil ? .running : .succeeded,
                        output: kept, progress: progress, localizedDurations: style.localizedDurations), block: block,
                    width: width, inset: inset, style: look)
            case .jobEnded(let label, let status, let lines):
                return blockHeader(
                    label,
                    metadata: blockMetadata(
                        status: status, output: "", progress: progress,
                        localizedDurations: style.localizedDurations, lineCount: lines),
                    block: block, width: width, inset: inset, style: Style(dim: true, italic: true))
            case .notice(let text, let isError):
                return rows(text, style: isError ? Style(fg: .indexed(1)) : Style(dim: true))
        }
    }

    /// A foldable block's body: hard lines 1 and on, drawn with the block's inset. What the block holds, not its own header line.
    private static func body(of text: String, block: Int, width: Int, inset: Int, style: Style) -> [Line] {
        guard !text.isEmpty else { return [] }
        let margin = String(repeating: " ", count: inset)
        return TextWrap.rows(text, width: width)
            .map { row in
                Line(
                    text: margin + row.text, style: style,
                    source: Source(
                        block: block, line: row.line + 1, offset: row.offset, col: inset, text: row.text))
            }
    }
}
