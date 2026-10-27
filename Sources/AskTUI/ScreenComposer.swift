public import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

/// Lays the screen out into a buffer: the transcript, bottom-aligned, then the prompt, then the status line below it.
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
        /// Click ownership, independent of selectable text (padding has no source).
        var foldBlock: Int?
        /// Runs of columns drawn in a style of their own over ``style``, such as a warning mark in colour.
        var accents: [Accent]

        init(text: String, style: Style, source: Source? = nil, accents: [Accent] = []) {
            self.text = text
            self.style = style
            self.source = source
            self.accents = accents
        }
    }

    /// A run of columns with a style of its own.
    struct Accent: Sendable, Equatable {
        var columns: Range<Int>
        var style: Style
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
        var accents: [Accent]
        /// The columns drawn selected, or nil.
        var highlight: Range<Int>?
        /// What the row carries at its right edge, if the sidebar is open.
        var side: Sidebar.Cell?
    }

    private var input = PromptLayout()

    /// Every transcript item's wrapped lines, end to end, rebuilt from the first item whose revision changed.
    var transcriptLines = LayoutCache<Line>()
    /// The look those lines were laid out for.
    var blockStyle = BlockStyle.plain
    private var foldBlocks: [Int?] = []
    /// Every item's hard lines, kept beside the wrapped lines so a selection can be read and highlighted.
    var hardLines: [[String]] = []
    /// What each row of the buffer holds since the last frame, and the size it was composed at.
    private var shown: [Shown?] = []
    private var shownSize = (columns: -1, rows: -1)

    /// Whether the last frame showed the cursor: not while the wheel has scrolled the input's window away from it.
    public private(set) var cursorIsVisible = true

    /// The rows the transcript took in the last frame, from the top: everything above the input (and the picker, when open).
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
        guard columns > 0, rows > 0 else {
            transcriptRows = 0
            frames?.store(FrameGeometry(columns: columns))
            return (0, 0)
        }
        if shownSize != (columns, rows) {
            shown = Array(repeating: nil, count: rows)
            shownSize = (columns, rows)
        }
        let editor = input.frame(
            state.editor, prompt: state.promptPrefix, columns: columns, screenRows: rows, maximumRows: state.promptRows,
            selection: state.inputSelection, scrollTop: state.promptScroll)
        cursorIsVisible = editor.cursorVisible
        let promptRows = editor.lines.count
        let statusRows = rows > 1 ? 1 : 0
        // Character rules enclose the input without extra blank rows.
        let ruleRows = state.separator && rows >= 6 ? 2 : 0
        let upperRuleRows = ruleRows / 2
        let strip = RunnerStrip(
            state, available: Swift.max(0, rows - promptRows - statusRows - ruleRows - 2), columns: columns)
        let panel = strip.lines.isEmpty ? [] : [Line(text: "", style: .default)] + strip.lines
        let status = Self.status(for: state, input: editor.indicator, columns: columns)
        let pickerRows = rows - promptRows - statusRows - ruleRows - panel.count - 1
        let pickerLines = Self.pickerLines(for: state, columns: columns, rows: pickerRows)
        let transcriptRows = rows - promptRows - statusRows - ruleRows - panel.count - pickerLines.count
        self.transcriptRows = transcriptRows

        let (sidebar, map, totalLines) = writeTranscript(
            state, rows: rows, transcriptRows: transcriptRows, columns: columns, into: &buffer)
        var geometry = FrameGeometry(
            rows: map, foldBlocks: foldBlocks, transcriptRows: transcriptRows, columns: columns, totalLines: totalLines,
            scrollback: state.scrollback,
            statusRow: transcriptRows + ruleRows + pickerLines.count + promptRows, runnerColumns: status.runners,
            belowColumns: status.below, promptRow: transcriptRows + upperRuleRows + pickerLines.count,
            promptRows: promptRows,
            promptTop: editor.top, prompt: editor.layout
        )
        .withPicker(state: state, firstRow: transcriptRows + upperRuleRows + 1, rows: pickerRows)
        geometry.placeStrip(strip, firstRow: rows - strip.lines.count)
        geometry.placeSidebar(sidebar, columns: columns)
        frames?.store(geometry)

        return writeBottom(
            panel: panel, status: statusRows > 0 ? status.line : nil, picker: pickerLines, editor: editor,
            rule: ruleRows > 0
                ? Line(text: String(repeating: "─", count: columns), style: StatusLine.statusStyle) : nil,
            inputStyle: Style(bg: ruleRows > 0 ? .default : state.theme.inputBackground), from: transcriptRows,
            into: &buffer)
    }

    /// Draws the transcript's visible rows, with the sidebar beside them, and says what each row shows.
    private mutating func writeTranscript(
        _ state: ScreenState, rows: Int, transcriptRows: Int, columns: Int, into buffer: inout ScreenBuffer
    ) -> (sidebar: Sidebar, map: RowMap<Int>, totalLines: Int) {
        let sidebar = Sidebar(state, columns: columns, rows: transcriptRows)
        let wrapColumns = sidebar.transcriptColumns(of: columns)
        updateTranscriptLines(state.transcript, columns: wrapColumns, style: state.blocks)
        let flat = transcriptLines.lines
        let end = Swift.max(0, flat.count - state.scrollback)
        let start = Swift.max(0, end - transcriptRows)
        let visible = flat[start ..< end]
        let map = Self.provenance(of: visible, rows: rows, transcriptRows: transcriptRows)
        foldBlocks = Array(repeating: nil, count: transcriptRows - visible.count) + visible.map(\.foldBlock)
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
            write(
                line, highlight: highlights[row], side: sidebar.cells.isEmpty ? nil : sidebar.cells[row], row: row,
                into: &buffer)
        }
        return (sidebar, map, flat.count)
    }

    /// Writes a whole row, the text then blanks to the edge, unless the row already holds exactly this.
    mutating func write(
        _ line: Line, highlight: Range<Int>? = nil, side: Sidebar.Cell? = nil, row: Int, into buffer: inout ScreenBuffer
    ) {
        let now = Shown(text: line.text, style: line.style, accents: line.accents, highlight: highlight, side: side)
        guard shown[row] != now else { return }
        shown[row] = now
        var column = 0
        for (part, style) in Self.spans(of: line, highlight: highlight) {
            buffer.write(part, row: row, col: column, style: style)
            column += UnicodeWidth.displayWidth(of: part)
        }
        let edge = side?.column ?? buffer.columns
        let used = Swift.min(edge, UnicodeWidth.displayWidth(of: line.text))
        if used < buffer.columns {
            // The rest of the row carries the row's own background, so a tinted block is tinted to the edge.
            buffer.fill(
                row: row, col: used, width: buffer.columns - used, height: 1,
                cell: Cell(character: " ", style: Style(bg: line.style.bg), width: 1))
        }
        if let side {
            buffer.write("│", row: row, col: side.column, style: Style(dim: true))
            buffer.write(side.text, row: row, col: side.column + 1, style: side.style)
        }
    }
}
