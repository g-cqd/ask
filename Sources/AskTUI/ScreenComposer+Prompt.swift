internal import TerminalKitText

extension ScreenComposer {
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
}
