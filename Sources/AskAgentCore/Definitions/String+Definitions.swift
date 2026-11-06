/// Small text helpers for definition files. None of them can fail.
extension String {
    /// The text without white space at either end.
    func trimmingWhitespace() -> String {
        var text = Substring(self)
        while let first = text.first, first.isWhitespace { text = text.dropFirst() }
        while let last = text.last, last.isWhitespace { text = text.dropLast() }
        return String(text)
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

    /// A key reduced to what it means: lower case, with `-`, `_` and spaces dropped, so `allowed-tools`, `allowed_tools` and `allowedTools` are one.
    var canonicalKey: String {
        String(lowercased().filter { $0 != "-" && $0 != "_" && $0 != " " })
    }
}
