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
        /// Whether a click on the row toggles the middle of a long tool output rather than the whole block (roadmap 0078).
        var foldsMiddle = false
        /// Runs of columns drawn in a style of their own over ``style``, such as a warning mark in colour.
        var accents: [Accent]
        /// File paths in the row, drawn as terminal hyperlinks over whatever style the column has.
        var links: [PathLinks.Link] = []
        /// Every stretch of the item's text the row shows, for a row of rendered Markdown that hides markers and adds chrome between them
        /// (roadmap 0065); empty for a row that shows one stretch as written, which ``source`` describes.
        var segments: [RowSegment] = []

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
    struct Shown: Equatable {
        var text: String
        var style: Style
        var accents: [Accent]
        var links: [PathLinks.Link]
        /// The columns drawn selected, or nil.
        var highlight: Range<Int>?
        /// What the row carries at its right edge, if the sidebar is open.
        var side: Sidebar.Cell?
    }

    private var input = PromptLayout()

    /// The last transcript items' heights, as far up as the shown rows reach, and the wrapped lines of those near them.
    var transcriptLines = WindowedLayout<Line>()
    /// The main conversation's layout, kept aside while a lane shows a runner (note n29), and the lane shown at the last frame.
    var mainLines: WindowedLayout<Line>?
    var shownLane: String?
    /// The look those lines were laid out for.
    var blockStyle = BlockStyle.plain
    var foldBlocks: [Int?] = []
    var middleFolds: [Bool] = []
    var rowLinks: [[PathLinks.Link]] = []
    /// What each row of the buffer holds since the last frame, and the size it was composed at.
    var shown: [Shown?] = []
    private var shownSize = (columns: -1, rows: -1)
    /// The theme the shown rows were drawn in; a new one redraws every row, because their colours come from it.
    var theme: ScreenTheme?

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

    /// The input's frame for `state`, after forgetting every row shown when the size or the theme changed.
    private mutating func inputFrame(for state: ScreenState, columns: Int, rows: Int) -> PromptLayout.Frame {
        if shownSize != (columns, rows) || theme != state.theme {
            shown = Array(repeating: nil, count: rows)
            shownSize = (columns, rows)
            theme = state.theme
        }
        let editor = input.frame(
            state.editor,
            prompt: state.promptPrefix,
            columns: columns,
            screenRows: rows,
            maximumRows: state.promptRows,
            selection: state.inputSelection,
            scrollTop: state.promptScroll,
            markdown: state.transcript.markdown,
            skills: state.transcript.tokenNames
        )
        cursorIsVisible = editor.cursorVisible
        return editor
    }

    /// The box around the input (note n36) when `ui.separator` asks for one and there is room: a border row above and below the input,
    /// taking no blank rows, and two columns each side.
    static func inputBox(for state: ScreenState, width: Int, rows: Int) -> InputBox? {
        guard state.separator, rows >= 6, width >= 8 else { return nil }
        return InputBox(width: width, style: state.theme.inputBorder(state.inputBorder, seed: state.sessionIdentity))
    }

    /// Writes `state` into `buffer`.
    /// - Returns: where the cursor belongs: in the prompt, at the editor's cursor.
    public mutating func compose(_ state: ScreenState, into buffer: inout ScreenBuffer) -> (row: Int, column: Int) {
        let (columns, rows) = (buffer.columns, buffer.rows)
        guard columns > 0, rows > 0 else {
            transcriptRows = 0
            frames?.store(FrameGeometry(columns: columns))
            return (0, 0)
        }
        // The sidebar in the bottom band (note n39): beside the input, which is that much narrower and as tall as the band.
        let band = Sidebar.band(state, columns: columns, screenRows: rows)
        let beside = band.map { columns - $0.width - 1 } ?? columns
        let box = Self.inputBox(for: state, width: beside, rows: rows)
        let editor = inputFrame(for: state, columns: box.map { $0.width - 4 } ?? beside, rows: rows)
        let promptRows = Swift.max(editor.lines.count, band?.cells.count ?? 0)
        let statusRows = rows > 1 ? 1 : 0
        let ruleRows = box == nil ? 0 : 2
        let strip = Self.strip(
            for: state,
            available: Swift.max(0, rows - promptRows - statusRows - ruleRows - 2),
            columns: columns
        )
        let panel = strip.lines.isEmpty ? [] : [Line(text: "", style: .default)] + strip.lines
        let status = Self.status(for: state, input: editor.indicator, columns: columns, trailingRunners: band != nil)
        let pickerRows = rows - promptRows - statusRows - ruleRows - panel.count - 1
        let pickerLines = Self.pickerLines(for: state, columns: columns, rows: pickerRows)
        let transcriptRows = rows - promptRows - statusRows - ruleRows - panel.count - pickerLines.count
        self.transcriptRows = transcriptRows
        var layout = BottomRows(columns, rows, transcriptRows, ruleRows, pickerLines.count, pickerRows, promptRows)
        layout.inset = box == nil ? 0 : 2

        let (sidebar, map, totalLines) = writeTranscript(
            state,
            rows: rows,
            columns: columns,
            besideTranscript: band == nil,
            into: &buffer
        )
        frames?
            .store(
                geometry(
                    state,
                    map: map,
                    totalLines: totalLines,
                    layout: layout,
                    status: status,
                    editor: editor,
                    strip: strip,
                    sidebar: band ?? sidebar,
                    inBand: band != nil
                )
            )

        return writeBottom(
            panel: panel,
            status: statusRows > 0 ? status.line : nil,
            picker: pickerLines,
            editor: editor,
            band: band?.cells ?? [],
            box: box,
            inputStyle: Style(bg: ruleRows > 0 ? .default : state.theme.inputBackground),
            from: transcriptRows,
            into: &buffer
        )
    }
}
