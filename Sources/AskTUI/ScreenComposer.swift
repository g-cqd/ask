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
    struct Line: Sendable, Equatable {
        var text: String
        var style: Style
    }

    static let prompt = "ask> "
    static let maximumPromptRows = 6

    /// Every transcript item's wrapped lines, end to end, rebuilt from the first item whose revision changed.
    private var transcriptLines = LayoutCache<Line>()
    /// What each row of the buffer holds since the last frame, and the size it was composed at.
    private var shown: [Line?] = []
    private var shownSize = (columns: -1, rows: -1)

    /// The rows the transcript took in the last frame, from the top: everything above the status line.
    public private(set) var transcriptRows = 0

    /// An empty composer.
    public init() {}

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
        for row in 0 ..< transcriptRows {
            let index = row - (transcriptRows - visible.count)
            let line = index >= 0 ? visible[visible.startIndex + index] : Line(text: "", style: .default)
            write(line, row: row, into: &buffer)
        }

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
        transcriptLines.update(width: columns, revisions: transcript.revisions) {
            Self.lines(for: transcript.items[$0], columns: columns)
        }
    }

    static func lines(for item: Transcript.Item, columns: Int) -> [Line] {
        switch item {
            case .user(let text):
                let wrapped = TextWrap.lines(text, width: columns - 2)
                return [Line(text: "", style: .default)]
                    + wrapped.enumerated()
                    .map { Line(text: ($0.offset == 0 ? "› " : "  ") + $0.element, style: Style(bold: true)) }
            case .assistant(let text):
                return TextWrap.lines(text, width: columns).map { Line(text: $0, style: .default) }
            case .tool(let name, let summary, let status):
                let mark: String
                let style: Style
                switch status {
                    case .running: (mark, style) = (" …", Style(dim: true))
                    case .succeeded: (mark, style) = (" ✓", Style(fg: .indexed(2), dim: true))
                    case .failed(let reason): (mark, style) = (" ✗ " + reason, Style(fg: .indexed(1)))
                }
                return TextWrap.lines("▸ \(name) \(summary)\(mark)", width: columns)
                    .map { Line(text: $0, style: style) }
            case .notice(let text, let isError):
                let style = isError ? Style(fg: .indexed(1)) : Style(dim: true)
                return TextWrap.lines(text, width: columns).map { Line(text: $0, style: style) }
        }
    }

    /// The prompt's lines, the prefix included, and the cursor's line and column within them. Wrapped by
    /// display width, hard, so the cursor maps exactly.
    func promptLines(_ editor: PromptEditor, columns: Int) -> (lines: [String], cursorLine: Int, cursorColumn: Int) {
        var lines = [Self.prompt]
        var width = Self.prompt.count
        var cursor = (line: 0, column: width)
        for (offset, character) in editor.text.enumerated() {
            if offset == editor.cursor { cursor = (lines.count - 1, width) }
            if character == "\n" {
                lines.append("")
                width = 0
                continue
            }
            let characterWidth = UnicodeWidth.displayWidth(of: character)
            if width + characterWidth > columns {
                lines.append("")
                width = 0
            }
            lines[lines.count - 1].append(character)
            width += characterWidth
        }
        if editor.cursor == editor.text.count {
            if width >= columns {
                lines.append("")
                width = 0
            }
            cursor = (lines.count - 1, width)
        }
        return (lines, cursor.line, cursor.column)
    }

    /// Writes a whole row, the text then blanks to the edge, unless the row already holds exactly this line.
    private mutating func write(_ line: Line, row: Int, into buffer: inout ScreenBuffer) {
        guard shown[row] != line else { return }
        shown[row] = line
        buffer.write(line.text, row: row, col: 0, style: line.style)
        let used = Swift.min(buffer.columns, UnicodeWidth.displayWidth(of: line.text))
        if used < buffer.columns {
            // An inverse line (the status bar) stays inverse to the edge; anything else pads with blanks.
            let padding = line.style.inverse ? line.style : .default
            buffer.fill(row: row, col: used, width: buffer.columns - used, height: 1, cell: Cell(style: padding))
        }
    }
}
