internal import TerminalKitStyle
internal import TerminalKitText

extension ScreenComposer {
    /// A queued message (roadmap 0129): dim, no background, `<spinner> · ` before the text and the other rows hanging under it. The
    /// spinner stops and becomes `↩` when the message went back to the editor. A selection takes the text, not the mark.
    static func queuedLines(_ text: String, block: Int, width: Int, inset: Int, progress: BlockProgress?) -> [Line] {
        let mark = progress?.ended == nil ? (progress?.indicator ?? "|") : "↩"
        let lead = mark + StatusLine.separator
        let leadWidth = UnicodeWidth.displayWidth(of: lead)
        let margin = String(repeating: " ", count: inset)
        let hanging = String(repeating: " ", count: leadWidth)
        return TextWrap.rows(text, width: Swift.max(1, width - leadWidth))
            .enumerated()
            .map { index, row in
                Line(
                    text: margin + (index == 0 ? lead : hanging) + row.text, style: Style(dim: true),
                    source: Source(
                        block: block, line: row.line, offset: row.offset, col: inset + leadWidth, text: row.text))
            }
    }
}
