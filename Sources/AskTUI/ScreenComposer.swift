public import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

/// Lays the screen out into a buffer: the transcript, bottom-aligned, then a status line, then the prompt.
///
/// Work is proportional to what changed, not to the screen:
/// - the transcript's wrapped lines are kept flattened, and only lines from the first changed item onward are
///   rebuilt, so a streamed delta re-wraps only the item it extends;
/// - a row whose content is unchanged since the last frame is not rewritten, so a keystroke writes the prompt
///   row and nothing else.
///
/// The composer assumes it composes into the same buffer each frame. A size change resets it; call ``reset()``
/// before composing into a different buffer.
public struct ScreenComposer: Sendable {
    /// One row of the transcript, as drawn, and where in the conversation it came from.
    struct Line: Sendable, Equatable {
        var text: String
        var style: Style
        /// The item's text this row shows, or nil for a row with no content of its own (a blank, a prefix-only row).
        var source: Source?

        init(text: String, style: Style, source: Source? = nil) {
            self.text = text
            self.style = style
            self.source = source
        }
    }

    /// The part of an item's text a row shows (TerminalKit roadmap 0017): its item, hard line and grapheme offset, the column it
    /// starts at, and the text itself, without the prefix some rows carry.
    struct Source: Sendable, Equatable {
        var block: Int
        var line: Int
        var offset: Int
        var col: Int
        var text: String
    }

    /// What a buffer row holds: the part of a ``Line`` that can be seen. Provenance is not in it, so a row that only moved, with the
    /// same text, is not rewritten.
    private struct Shown: Equatable {
        var text: String
        var style: Style
        /// The columns drawn selected, or nil.
        var highlight: Range<Int>?
    }

    static let prompt = "ask> "
    static let maximumPromptRows = 6

    /// Every transcript item's wrapped lines, end to end, rebuilt from the first item whose revision changed.
    private var transcriptLines = LayoutCache<Line>()
    /// Every item's hard lines, kept beside the wrapped lines so a selection can be read and highlighted.
    private var hardLines: [[String]] = []
    /// What each row of the buffer holds since the last frame, and the size it was composed at.
    private var shown: [Shown?] = []
    private var shownSize = (columns: -1, rows: -1)

    /// The rows the transcript took in the last frame, from the top: everything above the status line.
    public private(set) var transcriptRows = 0

    /// Where each frame's geometry goes for the mouse, or nil when nothing reads it.
    private let frames: FrameBox?

    /// An empty composer.
    public init() { frames = nil }

    init(frames: FrameBox) { self.frames = frames }

    /// Forgets what the buffer holds, so the next frame writes every row.
    public mutating func reset() { shownSize = (-1, -1) }

    /// Writes `state` into `buffer`.
    /// - Returns: where the cursor belongs: in the prompt, at the editor's cursor.
    public mutating func compose(_ state: ScreenState, into buffer: inout ScreenBuffer) -> (row: Int, column: Int) {
        let (columns, rows) = (buffer.columns, buffer.rows)
        if shownSize != (columns, rows) {
            shown = Array(repeating: nil, count: rows)
            shownSize = (columns, rows)
        }
        let editor = promptLines(state.editor, columns: columns)
        let promptRows = Swift.min(editor.lines.count, Self.maximumPromptRows, Swift.max(1, rows - 1))
        let firstPromptLine = Swift.max(
            0, Swift.min(editor.cursorLine - promptRows + 1, editor.lines.count - promptRows))
        let transcriptRows = Swift.max(0, rows - promptRows - 1)
        self.transcriptRows = transcriptRows

        updateTranscriptLines(state.transcript, columns: columns)
        let flat = transcriptLines.lines
        let end = Swift.max(0, flat.count - state.scrollback)
        let start = Swift.max(0, end - transcriptRows)
        let visible = flat[start ..< end]
        var map = RowMap<Int>()
        map.reset(rowCount: rows)
        for row in 0 ..< transcriptRows {
            let index = row - (transcriptRows - visible.count)
            let line = index >= 0 ? visible[visible.startIndex + index] : Line(text: "", style: .default)
            if let source = line.source {
                map.set(
                    row: row,
                    to: RowProvenance(
                        block: source.block, ordinal: source.block, line: source.line, firstOffset: source.offset,
                        col: source.col, text: source.text))
            }
        }
        var highlights = [Range<Int>?](repeating: nil, count: transcriptRows)
        if let selection = state.selection {
            for span in map.highlights(of: selection, in: TranscriptContent(blocks: hardLines))
            where span.row < transcriptRows {
                highlights[span.row] = span.startCol ..< span.endCol
            }
        }
        for row in 0 ..< transcriptRows {
            let index = row - (transcriptRows - visible.count)
            let line = index >= 0 ? visible[visible.startIndex + index] : Line(text: "", style: .default)
            write(line, highlight: highlights[row], row: row, into: &buffer)
        }
        frames?
            .store(
                FrameGeometry(rows: map, transcriptRows: transcriptRows, columns: columns, totalLines: flat.count))

        let activity = state.running ? "\(state.label) · working… (esc to abort)" : "\(state.label) · ready"
        let status = state.detail.isEmpty ? activity : activity + " · " + state.detail
        write(Line(text: status, style: Style(dim: true, inverse: true)), row: transcriptRows, into: &buffer)

        for offset in 0 ..< promptRows {
            write(
                Line(text: editor.lines[firstPromptLine + offset], style: .default), row: transcriptRows + 1 + offset,
                into: &buffer)
        }
        return (transcriptRows + 1 + editor.cursorLine - firstPromptLine, editor.cursorColumn)
    }

    // MARK: - Lines

    private mutating func updateTranscriptLines(_ transcript: Transcript, columns: Int) {
        var hard = hardLines
        transcriptLines.update(width: columns, revisions: transcript.revisions) { index in
            let item = transcript.items[index]
            if hard.count <= index { hard.append(contentsOf: repeatElement([], count: index + 1 - hard.count)) }
            hard[index] = TranscriptContent.hardLines(of: transcript.contentText(at: index))
            return Self.lines(for: item, folded: transcript.isFolded(index), block: index, columns: columns)
        }
        hard.removeLast(Swift.max(0, hard.count - transcript.items.count))
        hardLines = hard
    }

    static func lines(for item: Transcript.Item, folded: Bool = false, block: Int = 0, columns: Int) -> [Line] {
        func rows(_ text: String, width: Int, col: Int, style: Style, prefix: (Int) -> String = { _ in "" }) -> [Line] {
            TextWrap.rows(text, width: width).enumerated()
                .map { number, row in
                    Line(
                        text: prefix(number) + row.text, style: style,
                        source: Source(block: block, line: row.line, offset: row.offset, col: col, text: row.text))
                }
        }
        switch item {
            case .user(let text):
                return [Line(text: "", style: .default)]
                    + rows(text, width: columns - 2, col: 2, style: Style(bold: true)) { $0 == 0 ? "› " : "  " }
            case .assistant(let text):
                return rows(text, width: columns, col: 0, style: .default)
            case .tool(let name, let summary, let status, let output):
                let style: Style
                switch status {
                    case .running: style = Style(dim: true)
                    case .succeeded: style = Style(fg: .indexed(2), dim: true)
                    case .failed: style = Style(fg: .indexed(1))
                }
                let header = Transcript.Item.toolHeader(
                    name: name, summary: summary, status: status, output: output, folded: folded)
                return rows(header, width: columns, col: 0, style: style)
                    + (folded ? [] : body(of: output, block: block, columns: columns, style: Style(dim: true)))
            case .thinking(let text):
                let kept = Transcript.kept(text)
                let style = Style(dim: true, italic: true)
                let header = Transcript.Item.thinkingHeader(body: kept, folded: folded)
                return rows(header, width: columns, col: 0, style: style)
                    + (folded ? [] : body(of: kept, block: block, columns: columns, style: style))
            case .notice(let text, let isError):
                let style = isError ? Style(fg: .indexed(1)) : Style(dim: true)
                return rows(text, width: columns, col: 0, style: style)
        }
    }

    /// A foldable block's body: hard lines 1 and on, drawn two columns in. What the block holds, not its own header line.
    private static func body(of text: String, block: Int, columns: Int, style: Style) -> [Line] {
        guard !text.isEmpty else { return [] }
        return TextWrap.rows(text, width: columns - 2)
            .map { row in
                Line(
                    text: "  " + row.text, style: style,
                    source: Source(block: block, line: row.line + 1, offset: row.offset, col: 2, text: row.text))
            }
    }

    /// Writes a whole row, the text then blanks to the edge, unless the row already holds exactly this.
    private mutating func write(
        _ line: Line, highlight: Range<Int>? = nil, row: Int, into buffer: inout ScreenBuffer
    ) {
        let now = Shown(text: line.text, style: line.style, highlight: highlight)
        guard shown[row] != now else { return }
        shown[row] = now
        if let highlight {
            // The selected cells are inverse, in the line's own style otherwise: nothing is painted but the selection.
            let parts = ColumnSlicer.split(line.text, columns: highlight)
            var selected = line.style
            selected.inverse = true
            var column = 0
            for (part, style) in [(parts.before, line.style), (parts.selected, selected), (parts.after, line.style)]
            where !part.isEmpty {
                buffer.write(part, row: row, col: column, style: style)
                column += UnicodeWidth.displayWidth(of: part)
            }
        } else {
            buffer.write(line.text, row: row, col: 0, style: line.style)
        }
        let used = Swift.min(buffer.columns, UnicodeWidth.displayWidth(of: line.text))
        if used < buffer.columns {
            // An inverse line (the status bar) stays inverse to the edge; anything else pads with blanks.
            let padding = line.style.inverse ? line.style : .default
            buffer.fill(row: row, col: used, width: buffer.columns - used, height: 1, cell: Cell(style: padding))
        }
    }
}
