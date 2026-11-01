internal import AemiMarkdown
internal import Foundation
internal import TerminalKitMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

/// Assistant messages drawn as Markdown (roadmap 0065, phase 4; `ui.markdown`): each top-level block laid out by TerminalKit's renderer, a blank
/// row between blocks, and a long fenced block folded to one dim line as it is with Markdown off (ADR-0046).
extension ScreenComposer {
    /// GitHub's Markdown without math: a reply that mentions two prices is not a formula.
    static let markdownExtensions: MarkdownExtensions = [.gfm, .alerts]

    /// The rows of the assistant message `text`, item `index` of `transcript`, drawn as Markdown at `columns`. `firstBlockWidth`, when
    /// given, is the width the first top-level block wraps at instead, so its first row leaves room beside it (a thinking block's status).
    static func markdownLines(
        _ text: String, in transcript: Transcript, at index: Int, columns: Int, style: BlockStyle,
        firstBlockWidth: Int? = nil
    ) -> [Line] {
        let inset = style.inset
        let width = Swift.max(1, columns - 2 * inset)
        let document = MarkdownParser.parse(Array(text.utf8), extensions: markdownExtensions)
        let fences = transcript.markdownFences(at: index) ?? []
        var renderer = MarkdownRenderer(
            theme: .standard, links: markdownLinks(home: transcript.home),
            highlighter: transcript.highlight ? CodeHighlighter.standard : nil, softBreaks: .lineBreak)
        var source = MarkdownSourceLines(text)
        var result: [Line] = []
        for block in document.topLevelBlocks {
            if !result.isEmpty { result.append(Line(text: "", style: .default)) }
            let fence =
                block.node.kind == .codeBlock
                ? longFence(of: block, in: document, fences: fences, source: &source) : nil
            // A folded block is its header alone: it is not laid out, nor coloured, only to be dropped.
            if let fence, fence.folded {
                result.append(foldHeader(fence.fence, block: index, inset: inset))
                continue
            }
            var rows = renderer.lines(of: block, in: document, width: result.isEmpty ? firstBlockWidth ?? width : width)
            if let fence {
                let header = foldHeader(fence.fence, block: index, inset: inset)
                // Open, the header takes the place of the language's row, and a click on it folds the block again.
                let label = renderer.theme.codeLabel
                while let first = rows.first, first.source == nil, first.runs.contains(where: { $0.style == label }) {
                    rows.removeFirst()
                }
                result.append(header)
            }
            result += rows.map { line(of: $0, block: index, inset: inset, source: &source) }
        }
        return result.isEmpty ? [Line(text: "", style: .default)] : result
    }

    /// The long fence a code block is, if it is one, found from its source rather than its rows, so a folded block need not be laid out:
    /// the block's first leaf is its info string, on the fence's line, or its first line of code, the line under it. A blank first line
    /// is an empty leaf that still has its place, where its row names no source. A block holds no range of its own, only its leaves.
    private static func longFence(
        of block: MarkdownBlock, in document: MarkdownDocument,
        fences: [(fence: CodeFence, ordinal: Int, folded: Bool)],
        source: inout MarkdownSourceLines
    ) -> (fence: CodeFence, ordinal: Int, folded: Bool)? {
        guard !fences.isEmpty else { return nil }
        for event in document.events(of: block) {
            guard case .leaf(let node) = event else { continue }
            let line = source.position(of: node.range.lowerBound).line
            let opening = node.kind == .infoString ? line : line - 1
            return fences.first { $0.fence.openingLine == opening }
        }
        return nil
    }

    /// The dim line a long block folds to, and heads it with when open: `code · swift · 34 lines`. It names the opening fence's line, which is
    /// what a click toggles (``Transcript/codeFence(toggledByLine:at:)``).
    private static func foldHeader(_ fence: CodeFence, block: Int, inset: Int) -> Line {
        let text = ShownCode.placeholder(for: fence)
        return Line(
            text: String(repeating: " ", count: inset) + text, style: Style(dim: true),
            source: Source(block: block, line: fence.openingLine, offset: 0, col: inset, text: ""))
    }

    /// Links to the web and mail as they are, and a link to an absolute or home path (with a `:line` or `:line:column` after it, as a compiler
    /// writes one) as a `file://` link, as tool output's paths are (roadmap 0075).
    static func markdownLinks(home: String?) -> MarkdownLinks {
        let home = home ?? NSHomeDirectory()
        return MarkdownLinks { target in
            guard target.hasPrefix("/") || target.hasPrefix("~/") else { return nil }
            return PathLinks.uri(withoutLocation(target), home: home)
        }
    }

    /// `path` without a trailing `:12` or `:12:5`.
    static func withoutLocation(_ path: String) -> String {
        var path = Substring(path)
        for _ in 0 ..< 2 {
            let digits = path.reversed().prefix { $0.isASCII && $0.isNumber }.count
            guard digits > 0, path.dropLast(digits).last == ":" else { break }
            path = path.dropLast(digits + 1)
        }
        return String(path)
    }
}
