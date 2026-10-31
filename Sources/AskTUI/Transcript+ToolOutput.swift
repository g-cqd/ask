internal import TerminalKitText

/// A long tool output folds its middle (roadmap 0078). The choice is kept with the code folds, under an ordinal no heredoc has, so
/// Ctrl+G reaches it and it survives the output growing; it is apart from the whole block's fold and from the input's heredocs.
extension Transcript {
    /// The code-fold ordinal of a tool's output; heredocs count from 0.
    static let outputFence = -1

    /// What an open tool block at `index` shows of its output, when the output is long enough to fold; nil otherwise.
    func shownToolOutput(at index: Int) -> ShownToolOutput? {
        guard !isFolded(index), case .tool(_, _, _, let output, _) = items[index], !output.isEmpty else { return nil }
        let folded = codeFolds.isFolded(CodeBlockID(item: index, fence: Self.outputFence), default: codeFoldedByDefault)
        let shown = ShownToolOutput(output, maxLines: outputFoldLines, maxBytes: outputFoldBytes, folded: folded)
        return shown.markerLine == nil ? nil : shown
    }

    /// The item's hard line the marker goes before: the output is last in the item's text, so it counts back from the end.
    func outputMarkerLine(at index: Int, _ shown: ShownToolOutput) -> Int {
        let total = TranscriptContent.hardLineCount(of: contentText(at: index))
        let outputLines = shown.text.isEmpty ? 0 : TranscriptContent.hardLineCount(of: shown.text)
        return total - outputLines + (shown.markerLine ?? 0)
    }

    /// Sets the limits past which a tool's output folds its middle; every tool block with output is laid out again.
    public mutating func setOutputFoldLimits(lines: Int, bytes: Int) {
        let lines = Swift.max(2, lines)
        let bytes = Swift.max(64, bytes)
        guard lines != outputFoldLines || bytes != outputFoldBytes else { return }
        outputFoldLines = lines
        outputFoldBytes = bytes
        for index in items.indices {
            if case .tool(_, _, _, let output, _) = items[index], !output.isEmpty { revisions[index] = bump() }
        }
    }
}
