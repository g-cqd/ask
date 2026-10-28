internal import TerminalKitCodecs
internal import TerminalKitInput

extension PromptEditor {
    /// The forward Delete key (CSI 3 ~) as TerminalKit decodes it, kitty's 57349. The kit keeps the name private (TerminalKit roadmap 0020).
    static let forwardDelete: UInt32 = 57_349

    /// Option (alt or meta) with a key: Left/Right or b/f move by word, Backspace deletes the word before the cursor and Delete the one
    /// after it (roadmap 0095). Terminals send Option+Backspace as ESC DEL, ESC BS, or a kitty alt modifier. Nil for anything else.
    mutating func optionKey(_ key: KeyEvent) -> Outcome? {
        guard !key.modifiers.isDisjoint(with: [.alt, .meta]) else { return nil }
        switch key.keyCode {
            case 0x7F, 0x08: deleteWordBackward()
            case Self.forwardDelete: deleteWordForward()
            case Key.left.rawValue, 0x62, 0x42: moveWordBackward()
            case Key.right.rawValue, 0x66, 0x46: moveWordForward()
            default: return nil
        }
        return .edited
    }

    /// Deletes back to the start of the word before the cursor, over the spaces and line breaks in between, as Ctrl+W does.
    mutating func deleteWordBackward() {
        let characters = Array(text)
        var start = cursor
        while start > 0, characters[start - 1] == " " || characters[start - 1] == "\n" { start -= 1 }
        while start > 0, characters[start - 1] != " ", characters[start - 1] != "\n" { start -= 1 }
        remove(start ..< cursor)
    }

    /// Deletes forward to the end of the word after the cursor, over the spaces and line breaks before it.
    mutating func deleteWordForward() {
        let characters = Array(text)
        var end = cursor
        while end < characters.count, characters[end] == " " || characters[end] == "\n" { end += 1 }
        while end < characters.count, characters[end] != " ", characters[end] != "\n" { end += 1 }
        remove(cursor ..< end)
    }

    /// Moves backward by word, past preceding punctuation/spaces to word start.
    public mutating func moveWordBackward() {
        var pos = cursor
        let characters = Array(text)
        while pos > 0 && isWordBoundary(characters[pos - 1]) { pos -= 1 }
        while pos > 0 && !isWordBoundary(characters[pos - 1]) { pos -= 1 }
        move(to: pos)
    }

    /// Moves forward by word, past the current word and following spaces to next word start.
    public mutating func moveWordForward() {
        var pos = cursor
        let characters = Array(text)
        while pos < characters.count && !isWordBoundary(characters[pos]) { pos += 1 }
        while pos < characters.count && isWordBoundary(characters[pos]) { pos += 1 }
        move(to: pos)
    }

    private func isWordBoundary(_ char: Character) -> Bool {
        char.isWhitespace || char.isPunctuation
    }
}
