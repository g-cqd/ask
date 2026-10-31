internal import TerminalKitStyle

extension ScreenComposer {
    /// A thinking block's header row, folded or open (owner, 2026-10-31): `Thinking...`, then the block's status after the usual
    /// 4-cell spacer. Open, the reasoning follows on the rows below, and the header is drawn but not selected: the block's text is the
    /// reasoning, whose rows keep their own source lines from 0.
    static func thinkingHeaderRow(
        _ kept: String, folded: Bool, progress: BlockProgress?, block: Int, width: Int, style: BlockStyle
    ) -> [Line] {
        let inset = style.inset
        let open = !folded && Transcript.saysSomething(kept)
        var rows = blockHeader(
            Transcript.Item.thinkingHeader(body: kept, folded: folded),
            metadata: blockMetadata(
                status: progress?.ended == nil && progress != nil ? .running : .succeeded, output: kept,
                progress: progress, localizedDurations: style.localizedDurations),
            block: block, width: width, inset: inset, style: Style(dim: true, italic: true))
        if open { for row in rows.indices { rows[row].source = nil } }
        return rows
    }
}
