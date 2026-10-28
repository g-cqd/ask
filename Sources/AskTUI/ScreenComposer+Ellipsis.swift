internal import TerminalKitText

/// One way to cut text to a width, shared by tool headers (roadmap 0080) and job rows (roadmap 0100).
extension ScreenComposer {
    /// `text` in at most `cells` display cells: whole when it fits, else cut at a character and ended with `…`, the ellipsis counted in the
    /// cells. `shown` is the text without the ellipsis, which is what a selection takes; `cells` is the width of `shown` plus `mark`.
    static func ellipsized(_ text: String, cells room: Int) -> (shown: String, mark: String, cells: Int) {
        guard room > 0 else { return ("", "", 0) }
        if UnicodeWidth.displayWidth(of: text) <= room { return (text, "", UnicodeWidth.displayWidth(of: text)) }
        var shown = ""
        var used = 0
        for character in text {
            let next = UnicodeWidth.displayWidth(of: String(character))
            guard used + next <= room - 1 else { break }
            shown.append(character)
            used += next
        }
        return (shown, "…", used + 1)
    }
}
