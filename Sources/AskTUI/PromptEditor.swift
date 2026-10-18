public import TerminalKitCodecs
internal import TerminalKitInput
internal import TerminalKitText

/// The text being typed, with a cursor, and the familiar line-editing keys.
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

    /// An empty editor.
    public init() {}

    /// Applies one key.
    public mutating func apply(_ key: KeyEvent) -> Outcome {
        let code = key.keyCode
        if key.modifiers.contains(.ctrl), let scalar = Unicode.Scalar(code), scalar.isASCII {
            return control(UInt32(scalar.value & 0x1F))
        }
        switch code {
            case 0x00 ... 0x1A, 0x7F: return control(code)
            case 0x1B: return .escape
            case Key.left.rawValue: move(to: cursor - 1)
            case Key.right.rawValue: move(to: cursor + 1)
            case Key.home.rawValue: move(to: 0)
            case Key.end.rawValue: move(to: text.count)
            default:
                let inserted =
                    key.associatedText.isEmpty ? Unicode.Scalar(code).map { String(Character($0)) } : key.associatedText
                guard let inserted, code >= 0x20, !(0xE000 ... 0xF8FF).contains(code) else { return .ignored }
                insert(inserted)
        }
        return .edited
    }

    /// Inserts pasted text at the cursor. Line breaks become spaces: the prompt is one message.
    public mutating func paste(_ pasted: String) {
        insert(pasted.replacing("\r\n", with: " ").replacing("\n", with: " ").replacing("\r", with: " "))
    }

    private mutating func control(_ code: UInt32) -> Outcome {
        switch code {
            case 0x03: return .interrupt
            case 0x04: return text.isEmpty ? .endOfInput : delete(forward: true)
            case 0x0D, 0x0A:
                let submitted = text
                guard submitted.contains(where: { !$0.isWhitespace }) else { return .ignored }
                text = ""
                cursor = 0
                return .submitted(submitted)
            case 0x7F, 0x08: return delete(forward: false)
            case 0x01: move(to: 0)
            case 0x05: move(to: text.count)
            case 0x02: move(to: cursor - 1)
            case 0x06: move(to: cursor + 1)
            case 0x15:  // Ctrl-U: delete to the start
                text.removeSubrange(text.startIndex ..< index(cursor))
                cursor = 0
            case 0x0B:  // Ctrl-K: delete to the end
                text.removeSubrange(index(cursor)...)
            case 0x17: deleteWordBackward()
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
        while start > 0, characters[start - 1] == " " { start -= 1 }
        while start > 0, characters[start - 1] != " " { start -= 1 }
        text.removeSubrange(index(start) ..< index(cursor))
        cursor = start
    }

    private mutating func move(to position: Int) { cursor = Swift.min(Swift.max(0, position), text.count) }

    private func index(_ offset: Int) -> String.Index { text.index(text.startIndex, offsetBy: offset) }
}
