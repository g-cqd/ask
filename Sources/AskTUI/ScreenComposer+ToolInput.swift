internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    static func toolStatusStyle(_ status: Transcript.ToolStatus) -> Style {
        switch status {
            case .running: Style(dim: true)
            case .succeeded: Style(fg: .indexed(2), dim: true)
            case .failed: Style(fg: .indexed(1))
            case .interrupted: Style(fg: .indexed(208))
        }
    }

    /// The whole input in the default colour, then the output dimmed, a blank row before each and no labels (roadmap 0078).
    static func toolInputLines(
        item: Transcript.Item, input: String, block: Int, columns: Int, style: BlockStyle, context: ToolContext
    ) -> [Line] {
        guard case .tool(let name, let summary, let status, let output, _) = item else { return [] }
        let shownOutput = context.output ?? output
        let progress = context.progress
        let inset = style.inset
        let width = Swift.max(1, columns - 2 * inset)
        let look = toolStatusStyle(status)
        return blockHeader(
            Transcript.Item.toolHeader(name: name, summary: summary, status: status, output: output, folded: false),
            metadata: blockMetadata(
                status: status, output: output, progress: progress,
                localizedDurations: style.localizedDurations, toolName: name), block: block, width: width, inset: inset,
            style: look)
            + [Line(text: "", style: .default)]
            + body(of: input, block: block, width: width, inset: inset, style: .default)
            + (shownOutput.isEmpty
                ? []
                : [Line(text: "", style: .default)]
                    + body(
                        of: shownOutput, block: block, width: width, inset: inset, style: Style(dim: true),
                        firstLine: 1 + TranscriptContent.hardLineCount(of: input)))
    }
}
