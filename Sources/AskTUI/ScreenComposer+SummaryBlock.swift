internal import TerminalKitStyle
internal import TerminalKitText

/// A summary block opened (roadmap 0176): its header, then the summary drawn as Markdown and dim, as reasoning is. The summary's rows say
/// they show lines 1 and on of the block's text, under its header at line 0, so a selection copies the summary as written.
extension ScreenComposer {
    static func summaryBlockLines(in transcript: Transcript, at index: Int, columns: Int, style: BlockStyle) -> [Line]?
    {
        guard transcript.summaryBlocks.contains(index), !transcript.isFolded(index),
            case .tool(let name, let summary, let status, let output, _) = transcript.items[index], !output.isEmpty
        else { return nil }
        let width = Swift.max(1, columns - 2 * style.inset)
        let header = blockHeader(
            Transcript.Item.toolHeader(name: name, summary: summary, status: status, output: output, folded: false),
            metadata: blockMetadata(
                status: status,
                output: output,
                progress: transcript.progress[index],
                localizedDurations: style.localizedDurations,
                toolName: name
            ),
            block: index,
            width: width,
            inset: style.inset,
            style: toolStatusStyle(status)
        )
        // A summary ask wrote is dim, as reasoning is; an aside is the model's answer to the person, at full brightness.
        let dim = !transcript.asideBlocks.contains(index)
        let body = markdownLines(output, in: transcript, at: index, columns: columns, style: style)
            .map { row in
                var row = row
                if dim {
                    row.style.dim = true
                    for accent in row.accents.indices { row.accents[accent].style.dim = true }
                }
                if var source = row.source {
                    source.line += 1
                    row.source = source
                }
                for segment in row.segments.indices { row.segments[segment].line += 1 }
                return row
            }
        var rows = header + [Line(text: "", style: .default)] + body
        for row in rows.indices { rows[row].foldBlock = index }
        return rows
    }
}
