/// The shape an id, code or account name must have before it is put in a path, a header or a form.
enum PlainToken {
    /// Whether `value` is ASCII letters, ASCII digits and the marks in `extra`, with a byte length within `length`.
    ///
    /// ASCII only: a look-alike letter, a separator or a control character is how an id climbs out of the place it is
    /// put, or splits a header.
    static func matches(_ value: String, length: ClosedRange<Int>, extra: String) -> Bool {
        let marks = Set(extra.utf8)
        return length.contains(value.utf8.count)
            && value.utf8.allSatisfy {
                ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
                    || marks.contains($0)
            }
    }

    /// Whether `value` is a plain word: ASCII letters (lower-case only when `lowercase`), digits and the marks `.`, `_` and `-`,
    /// starting with a letter or a digit, within `length` bytes.
    ///
    /// The one rule behind model ids, alias names and connection names, so a leading mark cannot become a path or an option.
    static func word(_ value: String, length: ClosedRange<Int>, lowercase: Bool) -> Bool {
        guard matches(value, length: length, extra: "._-"), let first = value.utf8.first,
            ![0x2E, 0x5F, 0x2D].contains(first)
        else { return false }
        return !lowercase || !value.utf8.contains { $0 >= 0x41 && $0 <= 0x5A }
    }
}
