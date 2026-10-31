internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The rows an item is drawn as: its content, and with a padded style one row of padding around it (tinted to the edge when the kind has a tint),
    /// and a blank row above when this block and the one before are both tool calls or the user's messages.
    static func lines(
        for item: Transcript.Item, folded: Bool = false, block: Int = 0, columns: Int, style: BlockStyle = .plain,
        spacerAbove: Bool = false, progress: BlockProgress? = nil, toolInput: ShownToolInput? = nil,
        command: Bool = false, interrupted: Bool = false
    ) -> [Line] {
        let content = contentLines(
            for: item, folded: folded, block: block, columns: columns, style: style,
            context: (progress, toolInput, command))
        var result = framed(content, kind: item, style: style, spacerAbove: spacerAbove, interrupted: interrupted)
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
    static func framed(
        _ content: [Line], kind: Transcript.Item, style: BlockStyle, spacerAbove: Bool, interrupted: Bool = false
    ) -> [Line] {
        // Paths, web and email addresses become links in every block (roadmap 0075), beside a Markdown row's own links. Once per layout
        // of the block, not per frame; the row cache then redraws only what changed.
        let content = content.map(Self.linked)
        guard style.padded else { return content }
        let tint = interrupted && style.theme.tinted ? style.theme.interrupted : style.theme.tint(for: kind)
        func tinted(_ line: Line) -> Line {
            var line = line
            line.style.bg = tint
            return line
        }
        let padding = Line(text: "", style: Style(bg: tint))
        return (spacerAbove ? [Line(text: "", style: .default)] : []) + [padding] + content.map(tinted) + [padding]
    }

    /// `line` with the paths and addresses in its text linked, where no link of its own already is.
    static func linked(_ line: Line) -> Line {
        guard line.text.contains("/") || line.text.contains("@") || line.text.contains(":") else { return line }
        let found = PathLinks.links(in: line.text)
            .filter { link in
                !line.links.contains { $0.columns.overlaps(link.columns) }
            }
        guard !found.isEmpty else { return line }
        var line = line
        line.links = (line.links + found).sorted { $0.columns.lowerBound < $1.columns.lowerBound }
        return line
    }

    /// Whether the item is one of the kinds set apart by a blank row from a neighbour of the same sort.
    static func isSpaced(_ item: Transcript.Item) -> Bool {
        switch item {
            case .user, .tool: true
            case .notice(_, let isError): !isError
            default: false
        }
    }

    private static func contentLines(
        for item: Transcript.Item, folded: Bool, block: Int, columns: Int, style: BlockStyle,
        context: (progress: BlockProgress?, toolInput: ShownToolInput?, command: Bool)
    ) -> [Line] {
        let progress = context.progress
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
            case .tool:
                return toolContentLines(
                    item, folded: folded, block: block, columns: columns, style: style, context: context)
            case .thinking(let text):
                let kept = Transcript.kept(text)
                let look = Style(dim: true, italic: true)
                let header = thinkingHeaderRow(
                    kept, folded: folded, progress: progress, block: block, width: width, style: style)
                guard !folded, Transcript.saysSomething(kept) else { return header }
                return header + rows(kept, style: look)
            case .jobEnded(let label, let status, let lines):
                return blockHeader(
                    label,
                    metadata: blockMetadata(
                        status: status, output: "", progress: progress,
                        localizedDurations: style.localizedDurations, lineCount: lines),
                    block: block, width: width, inset: inset, style: Style(dim: true, italic: true))
            case .notice(let text, let isError):
                return rows(text, style: isError ? Style(fg: .indexed(1)) : Style(dim: true))
            case .queued(let text):
                return queuedLines(text, block: block, width: width, inset: inset, progress: progress)
        }
    }

    /// A foldable block's body: hard lines 1 and on, drawn with the block's inset. What the block holds, not its own header line.
    static func body(of text: String, block: Int, width: Int, inset: Int, style: Style, firstLine: Int = 1) -> [Line] {
        guard !text.isEmpty else { return [] }
        let margin = String(repeating: " ", count: inset)
        return TextWrap.rows(text, width: width)
            .map { row in
                Line(
                    text: margin + row.text, style: style,
                    source: Source(
                        block: block, line: row.line + firstLine, offset: row.offset, col: inset, text: row.text))
            }
    }
}
