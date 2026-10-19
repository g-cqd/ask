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
}
