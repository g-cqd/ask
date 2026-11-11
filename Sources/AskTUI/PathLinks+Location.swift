internal import TerminalKitText

/// The place written after a path (roadmap 0216): `a.swift:12` or `a.swift:12:5`, as a compiler writes it.
extension PathLinks {
    /// `address` with `location` (`:12` or `:12:5`) carried after it as `#L12C5`, for a link drawn on rows that may wrap: the
    /// place goes with the link whatever row it ends on. ``Link/init(columns:carrying:)`` takes it off again.
    static func carrying(_ location: String, on address: String) -> String {
        let numbers = location.split(separator: ":").compactMap { Int($0) }
        guard address.hasPrefix("file://"), let line = numbers.first else { return address }
        return address + "#L\(line)" + (numbers.count > 1 ? "C\(numbers[1])" : "")
    }

    /// `links` with the line and column each file link ends with, or is followed by, in `text`, the row they are drawn on. A reply's
    /// shortened path covers its place; a path in plain text is followed by it.
    static func located(_ links: [Link], in text: String) -> [Link] {
        guard links.contains(where: { $0.line == nil && $0.uri.hasPrefix("file://") }) else { return links }
        let characters = Array(text)
        // The column each character starts at, and one past the last.
        var starts: [Int] = []
        starts.reserveCapacity(characters.count + 1)
        var column = 0
        for character in characters {
            starts.append(column)
            column += UnicodeWidth.displayWidth(of: character)
        }
        starts.append(column)
        return links.map { link in
            guard link.line == nil, link.uri.hasPrefix("file://"),
                let low = starts.firstIndex(of: link.columns.lowerBound),
                let high = starts.firstIndex(of: link.columns.upperBound), low < high
            else { return link }
            guard let place = place(endOf: characters[low ..< high]) ?? place(startOf: characters[high...]) else {
                return link
            }
            var link = link
            (link.line, link.column) = place
            return link
        }
    }

    /// `:12` or `:12:5` at the start of `text`.
    private static func place(startOf text: ArraySlice<Character>) -> (Int, Int?)? {
        var rest = text
        guard let line = number(after: ":", in: &rest) else { return nil }
        return (line, number(after: ":", in: &rest))
    }

    /// `:12` or `:12:5` at the end of `text`, with something before it.
    private static func place(endOf text: ArraySlice<Character>) -> (Int, Int?)? {
        guard let colon = text.lastIndex(of: ":"), colon > text.startIndex else { return nil }
        var last = text[colon...]
        guard let second = number(after: ":", in: &last), last.isEmpty else { return nil }
        let before = text[..<colon]
        if let earlier = before.lastIndex(of: ":"), earlier > before.startIndex {
            var first = before[earlier...]
            if let line = number(after: ":", in: &first), first.isEmpty { return (line, second) }
        }
        return (second, nil)
    }

    /// The number after `mark` at the start of `text`, which is moved past both; nil, and `text` left alone, when there is none.
    private static func number(after mark: Character, in text: inout ArraySlice<Character>) -> Int? {
        guard text.first == mark else { return nil }
        let digits = text.dropFirst().prefix { $0.isASCII && $0.isNumber }
        // Nine digits at most: a place, not a number that could overflow.
        guard (1 ... 9).contains(digits.count), let value = Int(String(digits)) else { return nil }
        text = text.dropFirst(1 + digits.count)
        return value
    }
}
