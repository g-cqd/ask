internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The rows item `index` draws as, folds applied: what the screen shows, and what a fold toggle measures before and after.
    static func lines(in transcript: Transcript, at index: Int, columns: Int, style: BlockStyle = .plain) -> [Line] {
        lines(in: transcript, at: index, shown: transcript.shownCode(at: index), columns: columns, style: style)
    }

    /// The same, for a caller that has already worked out what an assistant message shows. A running block's header shimmers.
    static func lines(
        in transcript: Transcript,
        at index: Int,
        shown: ShownCode?,
        columns: Int,
        style: BlockStyle = .plain
    ) -> [Line] {
        // A block past `ui.historyLimit` draws nothing, but the newest of them says how many there are (note n29).
        if case .trimmed = transcript.items[index] {
            guard index == transcript.history.boundary else { return [] }
            let margin = String(repeating: " ", count: style.inset)
            return [Line(text: margin + HistoryTrim.notice(transcript.history.trimmed), style: Style(dim: true))]
        }
        var rows = stillLines(in: transcript, at: index, shown: shown, columns: columns, style: style)
        if case .user = transcript.items[index] { rows = withSkillTokens(rows, known: transcript.tokenNames) }
        guard transcript.shimmer, let progress = transcript.progress[index], progress.ended == nil else { return rows }
        return shimmering(
            rows,
            block: index,
            elapsed: progress.started.duration(to: progress.sampled),
            theme: style.theme
        )
    }

    private static func stillLines(
        in transcript: Transcript,
        at index: Int,
        shown: ShownCode?,
        columns: Int,
        style: BlockStyle
    ) -> [Line] {
        let item = transcript.items[index]
        let spaced = index > 0 && isSpaced(item) && isSpaced(transcript.items[index - 1])
        let interrupted = transcript.interrupted.contains(index)
        let aside = transcript.asideBlocks.contains(index)
        if let rows = markdownItemLines(in: transcript, at: index, columns: columns, style: style) {
            return framed(rows, kind: item, style: style, spacerAbove: spaced, interrupted: interrupted, aside: aside)
        }
        if transcript.markdown, case .assistant(let text) = item {
            return framed(
                markdownLines(text, in: transcript, at: index, columns: columns, style: style, paths: true),
                kind: item,
                style: style,
                spacerAbove: spaced
            )
        }
        guard let shown else {
            let output = transcript.shownToolOutput(at: index)
            let rows = lines(
                for: item,
                folded: transcript.isFolded(index),
                block: index,
                columns: columns,
                style: style,
                spacerAbove: spaced,
                progress: transcript.progress[index],
                toolInput: transcript.shownToolInput(at: index),
                command: transcript.commandBlocks.contains(index),
                interrupted: interrupted,
                aside: aside,
                toolOutput: output?.text,
                replacements: transcript.replacements[index],
                code: transcript.fileCode(at: index),
                images: transcript.toolImages[index] ?? [],
                placements: transcript.shownPlacements(at: index)
            )
            guard let output else { return rows }
            return withOutputMarker(
                rows,
                output,
                before: transcript.outputMarkerLine(at: index, output),
                block: index,
                columns: columns,
                style: style
            )
        }
        // A placeholder is dim, like the other folds' headers; the rest of the message, open code included, is as it was.
        let margin = String(repeating: " ", count: style.inset)
        let content = TextWrap.rows(shown.text, width: Swift.max(1, columns - 2 * style.inset))
            .map { row in
                Line(
                    text: margin + row.text,
                    style: shown.placeholders.contains(row.line) ? Style(dim: true) : .default,
                    source: Source(block: index, line: row.line, offset: row.offset, col: style.inset, text: row.text)
                )
            }
        return framed(content, kind: item, style: style, spacerAbove: spaced)
    }
}
