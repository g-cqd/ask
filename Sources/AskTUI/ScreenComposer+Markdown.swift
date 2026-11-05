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
    /// `lead` indents every row by that many more columns, for a mark the caller writes before the first.
    static func markdownLines(
        _ text: String,
        in transcript: Transcript,
        at index: Int,
        columns: Int,
        style: BlockStyle,
        firstBlockWidth: Int? = nil,
        lead: Int = 0
    ) -> [Line] {
        // `lead` more columns on the left, for a mark before the first row that the others hang under (a queued message's).
        let inset = style.inset + lead
        let width = Swift.max(1, columns - 2 * style.inset - lead)
        var layout = MarkdownMessageLayout(
            document: MarkdownParser.parse(Array(text.utf8), extensions: markdownExtensions),
            fences: (transcript.markdownFences(at: index) ?? [])
                .map {
                    MarkdownMessageLayout.Fence(fence: $0.fence, ordinal: $0.ordinal, folded: $0.folded)
                },
            renderer: MarkdownRenderer(
                theme: markdownTheme,
                links: markdownLinks(home: transcript.home),
                highlighter: transcript.highlight ? CodeHighlighter.standard : nil,
                softBreaks: .lineBreak
            ),
            source: MarkdownSourceLines(text),
            item: index,
            inset: inset
        )
        // A block drawn before from the same events and bytes keeps its rows (roadmap 0152).
        let cache = transcript.markdownRows
        let settings = MarkdownRowCache.Settings(
            item: index,
            columns: columns,
            inset: inset,
            firstBlockWidth: firstBlockWidth,
            highlight: transcript.highlight,
            home: transcript.home
        )
        let kept = cache.kept(for: settings, text: text)
        var blocks: [MarkdownRowCache.Block] = []
        var result: [Line] = []
        for (ordinal, block) in layout.document.topLevelBlocks.enumerated() {
            if ordinal > 0 { result.append(Line(text: "", style: .default)) }
            let events = Array(layout.document.events(of: block))
            let fence = layout.fence(of: block, events: events)
            let lines: [Line]
            if ordinal < kept.blocks.count,
                MarkdownRowCache.reuses(kept.blocks[ordinal], events: events, fence: fence, prefix: kept.prefix)
            {
                lines = kept.blocks[ordinal].lines
            } else {
                cache.countLayout()
                lines = layout.lines(of: block, fence: fence, width: ordinal == 0 ? firstBlockWidth ?? width : width)
            }
            blocks.append(
                MarkdownRowCache.Block(
                    events: events,
                    reach: MarkdownRowCache.reach(of: events),
                    fence: fence,
                    lines: lines
                )
            )
            result += lines
        }
        cache.keep(blocks, for: settings, text: text)
        return result.isEmpty ? [Line(text: "", style: .default)] : result
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
