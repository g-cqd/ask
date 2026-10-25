extension YAMLParser {
    /// The value written after a key (or a dash), whose line has been passed: `cursor` is the first line that has not been read. The value may
    /// be on the same line, or in the lines under it.
    mutating func value(_ cursor: inout Int, keyIndent: Int, rest: String) -> DefinitionValue {
        let (content, comment) = rest.splittingComment()
        if let comment, let hint = DefinitionFile.hint(fromComment: comment) { hints.append(hint) }
        let text = content.trimmingWhitespace()
        guard let first = text.first else { return nested(&cursor, keyIndent: keyIndent) }
        switch first {
            case "|", ">": return .text(blockScalar(&cursor, keyIndent: keyIndent, header: text))
            case "[", "{": return gathered(&cursor, text: text, isClosed: Self.isBalanced)
            case "\"", "'": return gathered(&cursor, text: text, isClosed: Self.isQuoteClosed)
            default: return .text(plainScalar(&cursor, keyIndent: keyIndent, first: text))
        }
    }

    /// What lies under a key with nothing after its colon: a list, a map, or nothing.
    mutating func nested(_ cursor: inout Int, keyIndent: Int) -> DefinitionValue {
        guard depth < Self.maximumDepth else {
            diagnostics.append("nesting deeper than \(Self.maximumDepth) levels was skipped")
            while cursor < lines.count, lines[cursor].isBlank || lines[cursor].indent > keyIndent { cursor += 1 }
            return .text("")
        }
        depth += 1
        defer { depth -= 1 }
        var next = cursor
        while next < lines.count, lines[next].isBlank || lines[next].isComment { next += 1 }
        collectHints(from: cursor ..< next)
        cursor = next
        guard next < lines.count else { return .text("") }
        let line = lines[next]
        if line.isItem, line.indent >= keyIndent { return blockList(&cursor, indent: line.indent) }
        if line.indent > keyIndent { return .map(mapping(&cursor, indent: line.indent)) }
        return .text("")
    }

    /// A plain scalar and the more-indented lines that continue it, folded to one line with spaces.
    mutating func plainScalar(_ cursor: inout Int, keyIndent: Int, first: String) -> String {
        var text = first
        while cursor < lines.count, !lines[cursor].isBlank, !lines[cursor].isComment, lines[cursor].indent > keyIndent {
            text += " " + lines[cursor].text.splittingComment().content
            cursor += 1
        }
        return text
    }

    /// A quoted scalar or a flow collection that may run over several lines, read once it closes (or the limit is reached).
    mutating func gathered(
        _ cursor: inout Int, text: String, isClosed: (String) -> Bool
    ) -> DefinitionValue {
        var gathered = text
        var count = 0
        while !isClosed(gathered), cursor < lines.count, count < Self.gatherLimit {
            gathered += " " + lines[cursor].text.splittingComment().content
            cursor += 1
            count += 1
        }
        if !isClosed(gathered) {
            diagnostics.append("a quoted value or list was never closed; it was read as far as it went")
        }
        return FlowParser.parse(gathered)
    }

    /// Whether every `[` and `{` outside quotes has been closed.
    static func isBalanced(_ text: String) -> Bool {
        var depth = 0
        var quote: Character?
        var escaped = false
        for character in text {
            if let open = quote {
                if escaped {
                    escaped = false
                } else if character == "\\", open == "\"" {
                    escaped = true
                } else if character == open {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "[" || character == "{" {
                depth += 1
            } else if character == "]" || character == "}" {
                depth -= 1
            }
        }
        return depth <= 0 && quote == nil
    }

    /// Whether the quote that opens `text` has been closed.
    static func isQuoteClosed(_ text: String) -> Bool {
        guard let open = text.first else { return true }
        var escaped = false
        var seen = 0
        for character in text.dropFirst() {
            if escaped {
                escaped = false
            } else if character == "\\", open == "\"" {
                escaped = true
            } else if character == open {
                seen += 1
                if open == "\"" || seen % 2 == 1 { return true }
            }
        }
        return false
    }
}
