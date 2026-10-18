internal import TerminalKitText

/// Wraps text to a display width: at spaces when a line has one, inside a word only when the word alone is too
/// wide. Widths are display columns (`UnicodeWidth`), so wide characters count as two.
public enum TextWrap {
    /// The lines of `text` no wider than `width`. Line feeds end lines; tabs become four spaces.
    public static func lines(_ text: String, width: Int) -> [String] {
        let width = Swift.max(1, width)
        var lines: [String] = []
        for paragraph in text.replacing("\t", with: "    ").split(separator: "\n", omittingEmptySubsequences: false) {
            wrap(paragraph, width: width, into: &lines)
        }
        return lines
    }

    private static func wrap(_ paragraph: Substring, width: Int, into lines: inout [String]) {
        var line = ""
        var lineWidth = 0
        var lastSpace: (index: String.Index, width: Int)?
        for character in paragraph {
            let characterWidth = UnicodeWidth.displayWidth(of: character)
            if lineWidth + characterWidth > width {
                if character == " " {
                    // The line is exactly full: break here, and the space is the break.
                    lines.append(line)
                    (line, lineWidth, lastSpace) = ("", 0, nil)
                    continue
                }
                if let space = lastSpace, space.index > line.startIndex {
                    // Break at the last space: the space itself is dropped, the rest carries over.
                    let carried = String(line[line.index(after: space.index)...])
                    lines.append(String(line[..<space.index]))
                    line = carried
                    lineWidth = lineWidth - space.width - 1
                } else {
                    lines.append(line)
                    line = ""
                    lineWidth = 0
                }
                lastSpace = nil
            }
            if character == " " { lastSpace = (line.endIndex, lineWidth) }
            line.append(character)
            lineWidth += characterWidth
        }
        lines.append(line)
    }
}
