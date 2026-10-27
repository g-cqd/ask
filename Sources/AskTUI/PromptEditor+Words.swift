internal import TerminalKitInput

extension PromptEditor {
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
