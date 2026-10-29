internal import TerminalKitStyle
internal import TerminalKitText

/// A tool block's header fills its row (roadmap 0080), and a command block opens in place: the command's first line stays where it was and the
/// rest of it continues below, so the command is never shown twice.
extension ScreenComposer {
    /// Cells between the header text and the status that trails it.
    static let headerGap = 4

    /// A header that is one row whatever its length: the text takes the row up to the gap before `metadata`, and text wider than that is cut
    /// with `…`, counted in display cells. A selection takes the text that is shown, not the ellipsis.
    static func oneRowHeader(
        _ text: String, metadata: String, block: Int, width: Int, inset: Int, style: Style
    ) -> [Line] {
        let flat = text.replacing("\n", with: " ")
        let status = ColumnSlicer.split(metadata, columns: 0 ..< width).selected
        let statusCells = UnicodeWidth.displayWidth(of: status)
        let available = Swift.max(0, width - statusCells - (status.isEmpty ? 0 : headerGap))
        let (shown, mark, cells) = ellipsized(flat, cells: available)
        let gap = String(repeating: " ", count: Swift.max(0, width - cells - statusCells))
        return [
            Line(
                text: String(repeating: " ", count: inset) + shown + mark + gap + status, style: style,
                source: Source(block: block, line: 0, offset: 0, col: inset, text: shown))
        ]
    }

    /// A tool block's rows: folded, its one-row header; open, a command block, or a tool's header, its input and its output.
    static func toolContentLines(
        _ item: Transcript.Item, folded: Bool, block: Int, columns: Int, style: BlockStyle,
        context: (progress: BlockProgress?, toolInput: ShownToolInput?, command: Bool)
    ) -> [Line] {
        guard case .tool(let name, let summary, let status, let output, let input) = item else { return [] }
        let inset = style.inset
        let width = Swift.max(1, columns - 2 * inset)
        let metadata = blockMetadata(
            status: status, output: output, progress: context.progress, localizedDurations: style.localizedDurations,
            toolName: name)
        if folded {
            let header =
                context.command
                ? Transcript.Item.commandHeader(name: name, parameters: summary, command: input, folded: true)
                : Transcript.Item.toolHeader(name: name, summary: summary, status: status, output: output, folded: true)
            return oneRowHeader(
                header, metadata: metadata, block: block, width: width, inset: inset, style: toolStatusStyle(status))
        }
        if context.command {
            return commandLines(
                item, block: block, width: width, inset: inset, style: style,
                context: (context.progress, context.toolInput))
        }
        if !input.isEmpty {
            return toolInputLines(
                item: item, input: context.toolInput?.text ?? ShownToolInput(input, isFolded: { _ in true }).text,
                block: block, columns: columns, style: style, progress: context.progress)
        }
        let header = Transcript.Item.toolHeader(
            name: name, summary: summary, status: status, output: output, folded: false)
        return openBlock(header, metadata: metadata, item: item, block: block, width: width, inset: inset)
    }

    /// An open command block: its header row starts the command, the command's other rows follow it, then the output.
    static func commandLines(
        _ item: Transcript.Item, block: Int, width: Int, inset: Int, style: BlockStyle,
        context: (progress: BlockProgress?, toolInput: ShownToolInput?)
    ) -> [Line] {
        guard case .tool(let name, let parameters, let status, let output, let input) = item else { return [] }
        let header = Transcript.Item.commandHeader(
            name: name, parameters: parameters, command: context.toolInput?.text ?? input, folded: false)
        let metadata = blockMetadata(
            status: status, output: output, progress: context.progress, localizedDurations: style.localizedDurations,
            toolName: name)
        let lead = Transcript.Item.commandHeader(name: name, parameters: parameters, command: "", folded: false).count
        let commandLines = TranscriptContent.hardLineCount(of: header)
        return openBlock(header, metadata: metadata, item: item, block: block, width: width, inset: inset)
            .map { brightened($0, block: block, lead: lead, commandLines: commandLines) }
    }

    /// Open, the command is the block's subject, so it is drawn at full brightness, not in the dim of the lead and the status. Only the
    /// rows of the command change: the header row from the end of the lead to the end of the command, and every row that continues it.
    private static func brightened(_ line: Line, block: Int, lead: Int, commandLines: Int) -> Line {
        guard let source = line.source, source.block == block, source.line < commandLines
        else { return line }
        var line = line
        guard source.line == 0, source.offset < lead else {
            line.style = commandStyle
            return line
        }
        let shown = source.text.dropFirst(lead - source.offset)
        let start = source.col + UnicodeWidth.displayWidth(of: String(source.text.prefix(lead - source.offset)))
        let end = start + UnicodeWidth.displayWidth(of: String(shown))
        if end > start { line.accents.append(Accent(columns: start ..< end, style: commandStyle)) }
        return line
    }

    /// The style of an open command: the terminal's own foreground, not dimmed.
    static let commandStyle = Style()

    /// An open tool block: its header, then a blank row and its output, dimmed, counted from the line after the header's last.
    private static func openBlock(
        _ header: String, metadata: String, item: Transcript.Item, block: Int, width: Int, inset: Int
    ) -> [Line] {
        guard case .tool(_, _, let status, let output, _) = item else { return [] }
        let lines = blockHeader(
            header, metadata: metadata, block: block, width: width, inset: inset, style: toolStatusStyle(status))
        guard !output.isEmpty else { return lines }
        return lines + [Line(text: "", style: .default)]
            + body(
                of: output, block: block, width: width, inset: inset, style: Style(dim: true),
                firstLine: TranscriptContent.hardLineCount(of: header))
    }
}
