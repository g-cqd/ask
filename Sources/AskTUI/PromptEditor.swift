public import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

/// The text being typed, with a cursor, and the familiar line-editing keys. The text may span several lines
/// (separated by `\n`): Shift-Enter or Ctrl-J starts one, a paste keeps its own, and display-aware Up/Down follow wrapped rows.
/// Home, End, Ctrl-A, Ctrl-E, Ctrl-U and Ctrl-K remain hard-line operations; Ctrl-X clears the whole draft.
public struct PromptEditor: Sendable, Equatable {
    /// What a key did, beyond editing.
    public enum Outcome: Sendable, Equatable {
        case edited
        case submitted(String)
        case interrupt  // Ctrl-C
        case endOfInput  // Ctrl-D on an empty line
        case escape
        case ignored
    }

    public private(set) var text = ""
    /// The cursor, as a count of characters before it.
    public private(set) var cursor = 0
    /// The column Up and Down aim for, kept across a line too short to hold it; nil when the last key was not a
    /// vertical move.
    private var goalColumn: Int?
    /// Width of the display-row map that supplied the remembered column; nil for hard-line navigation.
    private var goalWidth: Int?

    /// An empty editor.
    public init() {}

    /// Applies a key, optionally navigating by wrapped display rows.
    /// - Parameters:
    ///   - key: The decoded key.
    ///   - columns: The terminal width, or nil for the original hard-line navigation.
    ///   - firstRowIndent: Display cells reserved for the host's first-row prefix.
    /// - Returns: The editing or submission outcome.
    public mutating func apply(_ key: KeyEvent, columns: Int? = nil, firstRowIndent: Int = 0) -> Outcome {
        let code = key.keyCode
        if code != Key.up.rawValue, code != Key.down.rawValue {
            goalColumn = nil
            goalWidth = nil
        }
        if code == 0x0D, key.modifiers.contains(.shift) {
            insert("\n")
            return .edited
        }
        if key.modifiers.contains(.ctrl), let scalar = Unicode.Scalar(code), scalar.isASCII {
            return control(UInt32(scalar.value & 0x1F))
        }
        switch code {
            case 0x00 ... 0x1A, 0x7F: return control(code)
            case 0x1B: return .escape
            case Key.left.rawValue: move(to: cursor - 1)
            case Key.right.rawValue: move(to: cursor + 1)
            case Key.home.rawValue: move(to: lineStart())
            case Key.end.rawValue: move(to: lineEnd())
            case Key.up.rawValue: return moveVertically(by: -1, columns: columns, firstRowIndent: firstRowIndent)
            case Key.down.rawValue: return moveVertically(by: 1, columns: columns, firstRowIndent: firstRowIndent)
            default:
                let inserted =
                    key.associatedText.isEmpty ? Unicode.Scalar(code).map { String(Character($0)) } : key.associatedText
                guard let inserted, code >= 0x20, !(0xE000 ... 0xF8FF).contains(code) else { return .ignored }
                insert(inserted)
        }
        return .edited
    }

    /// Puts the cursor at a character offset, as a click does. What the last Up or Down remembered is forgotten.
    public mutating func place(cursor offset: Int) {
        goalColumn = nil
        goalWidth = nil
        move(to: offset)
    }

    /// Removes the characters in `range`, leaving the cursor where they were, as deleting a selection does.
    mutating func remove(_ range: Range<Int>) {
        goalColumn = nil
        goalWidth = nil
        let lower = Swift.min(range.lowerBound, text.count)
        text.removeSubrange(index(lower) ..< index(Swift.min(range.upperBound, text.count)))
        cursor = lower
    }

    /// Inserts pasted text at the cursor, keeping its line breaks (every kind becomes `\n`).
    public mutating func paste(_ pasted: String) {
        goalColumn = nil
        goalWidth = nil
        insert(pasted.replacing("\r\n", with: "\n").replacing("\r", with: "\n"))
    }

    /// Puts `replacement` where the characters in `range` were, and a space after it unless one already follows, with the cursor
    /// after that space. How a picker's choice gets into the draft.
    mutating func replace(_ range: Range<Int>, with replacement: String) {
        goalColumn = nil
        goalWidth = nil
        let lower = index(range.lowerBound)
        let upper = index(Swift.min(range.upperBound, text.count))
        let spaceFollows = upper < text.endIndex && text[upper] == " "
        text.replaceSubrange(lower ..< upper, with: spaceFollows ? replacement : replacement + " ")
        cursor = range.lowerBound + replacement.count + 1
    }

    /// Returns unsent input to the editor without flattening its message boundaries.
    mutating func restore(_ text: String) {
        goalColumn = nil
        goalWidth = nil
        self.text = text
        cursor = text.count
    }

    private mutating func control(_ code: UInt32) -> Outcome {
        switch code {
            case 0x03: return .interrupt
            case 0x04: return text.isEmpty ? .endOfInput : delete(forward: true)
            case 0x0A: insert("\n")
            case 0x0D:
                let submitted = text
                guard submitted.contains(where: { !$0.isWhitespace }) else { return .ignored }
                text = ""
                cursor = 0
                return .submitted(submitted)
            case 0x7F, 0x08: return delete(forward: false)
            case 0x01: move(to: lineStart())
            case 0x05: move(to: lineEnd())
            case 0x02: move(to: cursor - 1)
            case 0x06: move(to: cursor + 1)
            case 0x15:  // Ctrl-U: delete to the start of the line
                let start = lineStart()
                text.removeSubrange(index(start) ..< index(cursor))
                cursor = start
            case 0x0B:  // Ctrl-K: delete to the end of the line, or the line break when already there
                let end = lineEnd()
                let upTo = end == cursor ? Swift.min(end + 1, text.count) : end
                text.removeSubrange(index(cursor) ..< index(upTo))
            case 0x17: deleteWordBackward()
            case 0x18:  // Ctrl-X clears the whole draft; Ctrl-U remains line-local.
                guard !text.isEmpty else { return .ignored }
                text.removeAll(keepingCapacity: true)
                cursor = 0
            default: return .ignored
        }
        return .edited
    }

    private mutating func insert(_ inserted: String) {
        text.insert(contentsOf: inserted, at: index(cursor))
        cursor += inserted.count
    }

    private mutating func delete(forward: Bool) -> Outcome {
        let target = forward ? cursor : cursor - 1
        guard target >= 0, target < text.count else { return .ignored }
        text.remove(at: index(target))
        cursor = target
        return .edited
    }

    private mutating func deleteWordBackward() {
        var start = cursor
        let characters = Array(text)
        while start > 0, characters[start - 1] == " " || characters[start - 1] == "\n" { start -= 1 }
        while start > 0, characters[start - 1] != " ", characters[start - 1] != "\n" { start -= 1 }
        text.removeSubrange(index(start) ..< index(cursor))
        cursor = start
    }

    /// Where the cursor's line begins, as a character offset.
    private func lineStart() -> Int { lineStart(in: Array(text)) }

    private func lineStart(in characters: [Character]) -> Int {
        var start = cursor
        while start > 0, characters[start - 1] != "\n" { start -= 1 }
        return start
    }

    /// Where the cursor's line ends: the offset of its line break, or the end of the text.
    private func lineEnd() -> Int { lineEnd(in: Array(text)) }

    private func lineEnd(in characters: [Character]) -> Int {
        var end = cursor
        while end < characters.count, characters[end] != "\n" { end += 1 }
        return end
    }

    /// Moves to the same column on the line above or below, or reports that there is none.
    private mutating func moveVertically(by step: Int) -> Outcome {
        let characters = Array(text)
        var start = lineStart(in: characters)
        let column = goalColumn ?? cursor - start
        if step < 0 {
            guard start > 0 else { return .ignored }
            start -= 1
            while start > 0, characters[start - 1] != "\n" { start -= 1 }
        } else {
            var end = lineEnd(in: characters)
            guard end < characters.count else { return .ignored }
            end += 1
            start = end
        }
        var end = start
        while end < characters.count, characters[end] != "\n" { end += 1 }
        let target = Swift.min(start + column, end)
        move(to: target)
        goalColumn = column
        return .edited
    }

    /// Display-aware navigation shares the renderer's map. Without a width, keep the original hard-line API.
    private mutating func moveVertically(by step: Int, columns: Int?, firstRowIndent: Int) -> Outcome {
        guard let columns else {
            if goalWidth != nil { goalColumn = nil }
            goalWidth = nil
            return moveVertically(by: step)
        }
        let layout = InputLayout(text, columns: columns, firstRowIndent: firstRowIndent)
        let position = layout.position(at: cursor)
        let row = position.row + step
        guard layout.rows.indices.contains(row) else { return .ignored }
        let column = goalWidth == layout.columns ? (goalColumn ?? position.column) : position.column
        let target = layout.offset(atRow: row, column: column)
        guard target != cursor else { return .ignored }
        cursor = target
        goalColumn = column
        goalWidth = layout.columns
        return .edited
    }

    private mutating func move(to position: Int) { cursor = Swift.min(Swift.max(0, position), text.count) }

    private func index(_ offset: Int) -> String.Index { text.index(text.startIndex, offsetBy: offset) }
}
