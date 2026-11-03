internal import AemiMarkdown
internal import TerminalKitMarkdown
internal import TerminalKitStyle

/// One message's top-level blocks laid out as transcript rows (roadmap 0065, 0152): a long fenced block as its fold header alone when
/// folded, under it when open, every other block as the renderer draws it.
struct MarkdownMessageLayout {
    /// A long fenced block: its fence, its place among the message's long fences, and whether it is folded.
    struct Fence: Equatable, Sendable {
        var fence: CodeFence
        var ordinal: Int
        var folded: Bool
    }

    let document: MarkdownDocument
    let fences: [Fence]
    var renderer: MarkdownRenderer
    var source: MarkdownSourceLines
    /// The item the message is, which its rows name.
    let item: Int
    let inset: Int

    /// The long fence a code block is, if it is one, found from its source rather than its rows, so a folded block need not be laid out:
    /// the block's first leaf is its info string, on the fence's line, or its first line of code, the line under it. A blank first line
    /// is an empty leaf that still has its place, where its row names no source. A block holds no range of its own, only its leaves.
    mutating func fence(of block: MarkdownBlock, events: [MarkdownEvent]) -> Fence? {
        guard block.node.kind == .codeBlock, !fences.isEmpty else { return nil }
        for event in events {
            guard case .leaf(let node) = event else { continue }
            let line = source.position(of: node.range.lowerBound).line
            let opening = node.kind == .infoString ? line : line - 1
            return fences.first { $0.fence.openingLine == opening }
        }
        return nil
    }

    /// The rows of `block` at `width`. A folded block is its header alone: it is not laid out, nor coloured, only to be dropped.
    mutating func lines(of block: MarkdownBlock, fence: Fence?, width: Int) -> [ScreenComposer.Line] {
        if let fence, fence.folded { return [Self.foldHeader(fence.fence, block: item, inset: inset)] }
        var rows = renderer.lines(of: block, in: document, width: width)
        var result: [ScreenComposer.Line] = []
        if let fence {
            // Open, the header takes the place of the language's row, and a click on it folds the block again.
            let label = renderer.theme.codeLabel
            while let first = rows.first, first.source == nil, first.runs.contains(where: { $0.style == label }) {
                rows.removeFirst()
            }
            result.append(Self.foldHeader(fence.fence, block: item, inset: inset))
        }
        for row in rows { result.append(ScreenComposer.line(of: row, block: item, inset: inset, source: &source)) }
        return result
    }

    /// The dim line a long block folds to, and heads it with when open: `╭─ swift · 34 lines` (roadmap 0177). It names the opening fence's line,
    /// which is what a click toggles (``Transcript/codeFence(toggledByLine:at:)``).
    private static func foldHeader(_ fence: CodeFence, block: Int, inset: Int) -> ScreenComposer.Line {
        let text = ShownCode.cornerPlaceholder(for: fence, open: ScreenComposer.markdownTheme.codeOpen ?? "╭─ ")
        return ScreenComposer.Line(
            text: String(repeating: " ", count: inset) + text,
            style: Style(dim: true),
            source: ScreenComposer.Source(block: block, line: fence.openingLine, offset: 0, col: inset, text: "")
        )
    }
}
