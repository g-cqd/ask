internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    static func toolStatusStyle(_ status: Transcript.ToolStatus) -> Style {
        switch status {
            case .running: Style(dim: true)
            case .succeeded: Style(fg: .indexed(2), dim: true)
            case .failed: Style(fg: .indexed(1))
        }
    }

    /// Input/output sections have decorative labels/gaps, never copied as tool content.
    static func toolInputLines(
        item: Transcript.Item, input: String, block: Int, columns: Int, style: BlockStyle, progress: BlockProgress?
    ) -> [Line] {
        guard case .tool(let name, let summary, let status, let output, _) = item else { return [] }
        let inset = style.inset
        let width = Swift.max(1, columns - 2 * inset)
        let margin = String(repeating: " ", count: inset)
        func label(_ text: String) -> Line {
            Line(
                text: margin + ColumnSlicer.split("── \(text) ──", columns: 0 ..< width).selected,
                style: Style(dim: true))
        }
        let look = toolStatusStyle(status)
        return blockHeader(
            Transcript.Item.toolHeader(name: name, summary: summary, status: status, output: output, folded: false),
            metadata: blockMetadata(
                status: status, output: output, progress: progress,
                localizedDurations: style.localizedDurations), block: block, width: width, inset: inset, style: look)
            + [Line(text: "", style: .default), label("input")]
            + body(of: input, block: block, width: width, inset: inset, style: .default)
            + [Line(text: "", style: .default), label(output.isEmpty ? "output · empty" : "output")]
            + body(
                of: output, block: block, width: width, inset: inset, style: Style(dim: true),
                firstLine: 1 + TranscriptContent.hardLines(of: input).count)
    }
}
