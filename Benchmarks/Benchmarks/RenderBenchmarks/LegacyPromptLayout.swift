import TerminalKitText

/// The pre-0019 prompt row builder, retained only as a release benchmark reference. This is the old ScreenComposer+Prompt walk,
/// not a second implementation used by the application.
enum LegacyPromptLayout {
    static func rows(_ text: String, cursorOffset: Int, columns: Int) -> (lines: [String], row: Int, column: Int) {
        var lines = ["ask> "]
        var width = 5
        var cursor = (row: 0, column: width)
        for (offset, character) in text.enumerated() {
            if offset == cursorOffset { cursor = (lines.count - 1, width) }
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
        if cursorOffset == text.count {
            if width >= columns {
                lines.append("")
                width = 0
            }
            cursor = (lines.count - 1, width)
        }
        return (lines, cursor.row, cursor.column)
    }
}
