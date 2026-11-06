internal import Foundation
internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// The rows an item is drawn as: its content, and with a padded style one row of padding around it (tinted to the edge when the kind has a tint),
    /// and a blank row above when this block and the one before are both tool calls or the user's messages.
    static func lines(
        for item: Transcript.Item,
        folded: Bool = false,
        block: Int = 0,
        columns: Int,
        style: BlockStyle = .plain,
        spacerAbove: Bool = false,
        progress: BlockProgress? = nil,
        toolInput: ShownToolInput? = nil,
        command: Bool = false,
        interrupted: Bool = false,
        aside: Bool = false,
        toolOutput: String? = nil,
        replacements: Int? = nil,
        code: FileCode? = nil,
        images: [ToolImage] = [],
        placements: [ImagePlacement?] = []
    ) -> [Line] {
        let context = ToolContext(
            progress: progress,
            toolInput: toolInput,
            command: command,
            output: toolOutput,
            replacements: replacements,
            code: code,
            images: images,
            placements: placements
        )
        let content = contentLines(
            for: item,
            folded: folded,
            block: block,
            columns: columns,
            style: style,
            context: context
        )
        var result = framed(
            content,
            kind: item,
            style: style,
            spacerAbove: spacerAbove,
            interrupted: interrupted,
            aside: aside
        )
        switch item {
            case .tool, .thinking:
                for index in result.indices where !(style.padded && spacerAbove && index == 0) {
                    result[index].foldBlock = block
                }
            default: break
        }
        return result
    }

    /// Wraps every block, including command and authentication notices, in padding, tint and spacing.
    static func framed(
        _ content: [Line],
        kind: Transcript.Item,
        style: BlockStyle,
        spacerAbove: Bool,
        interrupted: Bool = false,
        aside: Bool = false
    ) -> [Line] {
        // Paths, web and email addresses become links in every block (roadmap 0075), beside a Markdown row's own links. Once per layout
        // of the block, not per frame; the row cache then redraws only what changed.
        let content = content.map { linked($0, home: style.home) }
        guard style.padded else { return content }
        let tint =
            !style.theme.tinted
            ? style.theme.tint(for: kind)
            : interrupted ? style.theme.interrupted : aside ? style.theme.aside : style.theme.tint(for: kind)
        // A row with a tint of its own, an edit's removed or added line, keeps it.
        func tinted(_ line: Line) -> Line {
            var line = line
            if line.style.bg == .default { line.style.bg = tint }
            return line
        }
        let padding = Line(text: "", style: Style(bg: tint))
        return (spacerAbove ? [Line(text: "", style: .default)] : []) + [padding] + content.map(tinted) + [padding]
    }

    /// `line` with the paths and addresses in its text linked, where no link of its own already is; `~` is `home`, or the account's home.
    static func linked(_ line: Line, home: String?) -> Line {
        guard LinkCandidates.mayHoldLink(line.text) else { return line }
        let found = PathLinks.links(in: line.text, home: home ?? NSHomeDirectory())
            .filter { link in
                !line.links.contains { $0.columns.overlaps(link.columns) }
            }
        guard !found.isEmpty else { return line }
        var line = line
        line.links = (line.links + found).sorted { $0.columns.lowerBound < $1.columns.lowerBound }
        return line
    }

    /// Whether the item is one of the kinds set apart by a blank row from a neighbour of the same sort.
    static func isSpaced(_ item: Transcript.Item) -> Bool {
        switch item {
            case .user, .tool: true
            case .notice(_, let isError): !isError
            default: false
        }
    }

    private static func contentLines(
        for item: Transcript.Item,
        folded: Bool,
        block: Int,
        columns: Int,
        style: BlockStyle,
        context: ToolContext
    ) -> [Line] {
        let progress = context.progress
        let inset = style.inset
        let width = Swift.max(1, columns - 2 * inset)
        let margin = String(repeating: " ", count: inset)
        func rows(_ text: String, style: Style) -> [Line] {
            TextWrap.rows(text, width: width)
                .map { row in
                    Line(
                        text: margin + row.text,
                        style: style,
                        source: Source(block: block, line: row.line, offset: row.offset, col: inset, text: row.text)
                    )
                }
        }
        switch item {
            case .user(let text):
                // The older look set the user's message off with a blank row above it; the padded one has a row of padding for that.
                return (style.padded ? [] : [Line(text: "", style: .default)]) + rows(text, style: Style(bold: true))
            case .assistant(let text):
                return rows(text, style: .default)
            case .tool:
                let content = toolContentLines(
                    item,
                    folded: folded,
                    block: block,
                    columns: columns,
                    style: style,
                    context: context
                )
                // Its pictures show whether the output is folded or not (the owner, 2026-11-06: shown at once).
                return withImageRows(
                    content,
                    images: context.images,
                    placements: context.placements,
                    block: block,
                    inset: style.inset
                )
            case .thinking(let text):
                return thinkingLines(text, folded: folded, block: block, width: width, style: style, progress: progress)
            case .jobEnded(let label, let status, let lines):
                return blockHeader(
                    label,
                    metadata: blockMetadata(
                        status: status,
                        output: "",
                        progress: progress,
                        localizedDurations: style.localizedDurations,
                        lineCount: lines
                    ),
                    block: block,
                    width: width,
                    inset: inset,
                    style: Style(dim: true, italic: true)
                )
            case .notice(let text, let isError):
                return rows(text, style: isError ? Style(fg: .indexed(1)) : Style(dim: true))
            case .queued(let text):
                return queuedLines(text, block: block, width: width, inset: inset, progress: progress)
        }
    }

    /// A thinking block's rows: folded, or when it says nothing, its header; open, what it says, dim and italic.
    private static func thinkingLines(
        _ text: String,
        folded: Bool,
        block: Int,
        width: Int,
        style: BlockStyle,
        progress: BlockProgress?
    ) -> [Line] {
        let kept = Transcript.kept(text)
        let running = progress?.ended == nil && progress != nil
        let header = Transcript.Item.thinkingHeader(running: running)
        return blockHeader(
            folded || !Transcript.saysSomething(kept) ? header : kept,
            metadata: blockMetadata(
                status: running ? .running : .succeeded,
                output: kept,
                progress: progress,
                localizedDurations: style.localizedDurations
            ),
            block: block,
            width: width,
            inset: style.inset,
            style: Style(dim: true, italic: true)
        )
    }

    /// A foldable block's body: hard lines 1 and on, drawn with the block's inset. What the block holds, not its own header line.
    /// With `code`, the text is a file's, its tokens coloured over `style`; with `diff`, an edit's, each row tinted by its line's
    /// marker (roadmap 0152, phase 3).
    static func body(
        of text: String,
        block: Int,
        width: Int,
        inset: Int,
        style: Style,
        firstLine: Int = 1,
        code: FileCode? = nil,
        diff: DiffLook? = nil
    ) -> [Line] {
        guard !text.isEmpty else { return [] }
        let margin = String(repeating: " ", count: inset)
        var accents = code.map { CodeAccents(text, code: $0) }
        let kinds = diff.map { DiffLook.kinds(of: text, format: $0.format) }
        return TextWrap.rows(text, width: width)
            .map { row in
                let kind = kinds.flatMap { $0.indices.contains(row.line) ? $0[row.line] : nil } ?? .kept
                let rowStyle = diff?.style(kind, over: style) ?? style
                let marker = row.offset == 0 ? diff?.marker(kind, inset: inset, over: rowStyle) : nil
                return Line(
                    text: margin + row.text,
                    style: rowStyle,
                    source: Source(
                        block: block,
                        line: row.line + firstLine,
                        offset: row.offset,
                        col: inset,
                        text: row.text
                    ),
                    accents: (marker.map { [$0] } ?? [])
                        + (accents?.accents(for: row, inset: inset, over: rowStyle) ?? [])
                )
            }
    }
}
