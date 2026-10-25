/// Small text helpers the definition readers share. None of them can fail.
extension String {
    func trimmingTrailingWhitespace() -> String {
        var end = endIndex
        while end > startIndex, self[index(before: end)].isWhitespace { end = index(before: end) }
        return String(self[..<end])
    }

    func trimmingWhitespace() -> String {
        var text = Substring(self)
        while let first = text.first, first.isWhitespace { text = text.dropFirst() }
        return String(text).trimmingTrailingWhitespace()
    }

    /// The text without any of `characters` at either end.
    func trimming(_ characters: Set<Character>) -> String {
        var text = Substring(self)
        while let first = text.first, characters.contains(first) { text = text.dropFirst() }
        while let last = text.last, characters.contains(last) { text = text.dropLast() }
        return String(text)
    }

    /// The text with one pair of matching quotes removed, if it is wrapped in them.
    func unquoted() -> String {
        guard count >= 2, let first, first == "\"" || first == "'" || first == "`", last == first else { return self }
        return String(dropFirst().dropLast())
    }

    /// The text up to a `#` that starts a comment (at the start, or after whitespace, and outside quotes), and the comment without its `#`.
    func splittingComment() -> (content: String, comment: String?) {
        var quote: Character?
        var previous: Character = " "
        var escaped = false
        var skipNext = false
        for index in indices {
            let character = self[index]
            defer { previous = character }
            if skipNext {
                skipNext = false
                continue
            }
            if let open = quote {
                if escaped {
                    escaped = false
                } else if character == "\\", open == "\"" {
                    escaped = true
                } else if character == open {
                    // A doubled single quote is an apostrophe inside the string, not its end.
                    if open == "'", self.index(after: index) < endIndex, self[self.index(after: index)] == "'" {
                        skipNext = true
                    } else {
                        quote = nil
                    }
                }
                continue
            }
            if (character == "\"" || character == "'")
                && (previous.isWhitespace || previous == "[" || previous == "," || previous == ":")
            {
                quote = character
            } else if character == "#", previous.isWhitespace || index == startIndex {
                return (String(self[..<index]).trimmingTrailingWhitespace(), String(self[self.index(after: index)...]))
            }
        }
        return (self, nil)
    }

    /// A key reduced to what it means: lower case, with `-`, `_` and spaces dropped, so `allowed-tools`, `allowed_tools` and `allowedTools` are one.
    var canonicalKey: String {
        String(lowercased().filter { $0 != "-" && $0 != "_" && $0 != " " })
    }

    /// `key SEPARATOR rest`: the key bare or quoted, then the separator (`:` in YAML, where a space or the end of the line must follow it, and `=` in
    /// TOML), then the rest of the line. Nil when there is no separator or no key.
    func splittingKey(at separator: Character, needsSpaceAfter: Bool) -> (key: String, rest: String)? {
        let characters = Array(self)
        var index = 0
        var key = ""
        if let open = characters.first, open == "\"" || open == "'" {
            index = 1
            while index < characters.count, characters[index] != open {
                key.append(characters[index])
                index += 1
            }
            index += 1
            while index < characters.count, characters[index] == " " { index += 1 }
            guard index < characters.count, characters[index] == separator else { return nil }
        } else {
            while index < characters.count {
                let follows =
                    index + 1 == characters.count || characters[index + 1] == " " || characters[index + 1] == "\t"
                if characters[index] == separator, !needsSpaceAfter || follows { break }
                key.append(characters[index])
                index += 1
            }
            guard index < characters.count else { return nil }
        }
        let trimmed = key.trimmingWhitespace()
        guard !trimmed.isEmpty else { return nil }
        return (trimmed, String(characters[(index + 1)...]).trimmingWhitespace())
    }

    /// How many columns the line is indented, counting a tab as two.
    var indentation: Int {
        var columns = 0
        for character in self {
            if character == " " { columns += 1 } else if character == "\t" { columns += 2 } else { break }
        }
        return columns
    }
}
