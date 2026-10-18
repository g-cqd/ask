public import TerminalKitRender
internal import TerminalKitStyle
internal import TerminalKitText

/// What the interactive screen shows.
public struct ScreenState: Sendable, Equatable {
    public var transcript = Transcript()
    public var editor = PromptEditor()
    /// Shown at the left of the status line, such as the model.
    public var label: String
    /// Whether a run is in progress: the status line says so and how to abort it.
    public var running = false
    /// How many wrapped lines the transcript is scrolled up from the bottom.
    public var scrollback = 0

    /// A screen with nothing in it yet.
    public init(label: String) { self.label = label }
}

/// Lays the screen out into a buffer: the transcript, bottom-aligned, then a status line, then the prompt.
///
/// Each transcript item's wrapped lines are cached by revision and width, so a keystroke re-wraps nothing but
/// the prompt, and a streamed delta re-wraps only the item it extends. Every visible row is written in full;
/// the renderer's diff then sends only the cells that changed.
public struct ScreenComposer: Sendable {
    struct Line: Sendable, Equatable {
        var text: String
        var style: Style
    }

    static let prompt = "ask> "
    static let maximumPromptRows = 6

    private var cache: [Int: (revision: Int, width: Int, lines: [Line])] = [:]

    /// An empty composer.
    public init() {}

    /// Writes `state` into `buffer`.
    /// - Returns: where the cursor belongs: in the prompt, at the editor's cursor.
    public mutating func compose(_ state: ScreenState, into buffer: inout ScreenBuffer) -> (row: Int, column: Int) {
        let (columns, rows) = (buffer.columns, buffer.rows)
        let editor = promptLines(state.editor, columns: columns)
        let promptRows = Swift.min(editor.lines.count, Self.maximumPromptRows, Swift.max(1, rows - 1))
        let firstPromptLine = Swift.max(
            0, Swift.min(editor.cursorLine - promptRows + 1, editor.lines.count - promptRows))
        let transcriptRows = Swift.max(0, rows - promptRows - 1)

        let lines = transcriptLines(state.transcript, columns: columns)
        let end = Swift.max(0, lines.count - state.scrollback)
        let start = Swift.max(0, end - transcriptRows)
        let visible = lines[start ..< end]
        for row in 0 ..< transcriptRows {
            let index = row - (transcriptRows - visible.count)
            let line = index >= 0 ? visible[visible.startIndex + index] : Line(text: "", style: .default)
            write(line, row: row, into: &buffer)
        }

        let status = state.running ? "\(state.label) · working… (esc to abort)" : "\(state.label) · ready"
        write(Line(text: status, style: Style(dim: true, inverse: true)), row: transcriptRows, into: &buffer)

        for offset in 0 ..< promptRows {
            write(
                Line(text: editor.lines[firstPromptLine + offset], style: .default), row: transcriptRows + 1 + offset,
                into: &buffer)
        }
        return (transcriptRows + 1 + editor.cursorLine - firstPromptLine, editor.cursorColumn)
    }

    // MARK: - Lines

    private mutating func transcriptLines(_ transcript: Transcript, columns: Int) -> [Line] {
        var all: [Line] = []
        for (index, item) in transcript.items.enumerated() {
            let revision = transcript.revisions[index]
            if let cached = cache[index], cached.revision == revision, cached.width == columns {
                all += cached.lines
                continue
            }
            let lines = Self.lines(for: item, columns: columns)
            cache[index] = (revision, columns, lines)
            all += lines
        }
        return all
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

    /// Writes a whole row: the text, then blanks to the edge, so nothing from an earlier frame survives.
    private func write(_ line: Line, row: Int, into buffer: inout ScreenBuffer) {
        buffer.write(line.text, row: row, col: 0, style: line.style)
        let used = Swift.min(buffer.columns, UnicodeWidth.displayWidth(of: line.text))
        if used < buffer.columns {
            // An inverse line (the status bar) stays inverse to the edge; anything else pads with blanks.
            let padding = line.style.inverse ? line.style : .default
            buffer.fill(row: row, col: used, width: buffer.columns - used, height: 1, cell: Cell(style: padding))
        }
    }
}
