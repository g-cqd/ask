/// The words of a run of prose that may be paths (roadmap 0215): where they are, the path, and a `:line` or `:line:column` after it.
extension PathDisplay {
    struct Word: Equatable {
        var bytes: Range<Int>
        var path: String
        var location: String
    }

    /// What may stand before a path, and what ends one, as in ``PathLinks``.
    private static let before: Set<UInt8> = Set(" \t\"'([=<`".utf8)
    private static let stops: Set<UInt8> = Set(" \t\"')]<>`,;|\n\r".utf8)

    static func words(in bytes: [UInt8]) -> [Word] {
        var result: [Word] = []
        var index = 0
        while index < bytes.count {
            guard index == 0 || before.contains(bytes[index - 1]), !stops.contains(bytes[index]) else {
                index += 1
                continue
            }
            var end = index
            while end < bytes.count, !stops.contains(bytes[end]) { end += 1 }
            if let word = word(bytes, index ..< end) { result.append(word) }
            index = end
        }
        return result
    }

    /// The path in `range`, without sentence punctuation after it and with its location apart; nil for a word that is not a path.
    private static func word(_ bytes: [UInt8], _ range: Range<Int>) -> Word? {
        var end = range.upperBound
        while end > range.lowerBound, Set(".:!?".utf8).contains(bytes[end - 1]) { end -= 1 }
        var pathEnd = end
        for _ in 0 ..< 2 {
            var digits = pathEnd
            while digits > range.lowerBound, (0x30 ... 0x39).contains(bytes[digits - 1]) { digits -= 1 }
            guard digits < pathEnd, digits > range.lowerBound, bytes[digits - 1] == UInt8(ascii: ":") else { break }
            pathEnd = digits - 1
        }
        let path = String(decoding: bytes[range.lowerBound ..< pathEnd], as: UTF8.self)
        guard isPath(path) else { return nil }
        let location = String(decoding: bytes[pathEnd ..< end], as: UTF8.self)
        return Word(bytes: range.lowerBound ..< end, path: path, location: location)
    }

    /// An absolute path of two parts or more, a `~/` path, or a relative one with a folder or an extension; never an address or an option.
    private static func isPath(_ path: String) -> Bool {
        guard !path.contains("://"), !path.contains("@"), !path.hasPrefix("-"), path.contains(where: \.isLetter) else {
            return false
        }
        if path.hasPrefix("//") { return false }
        if path.hasPrefix("/") { return path.dropFirst().contains("/") }
        if path.hasPrefix("~/") { return path.count > 2 }
        if path.contains("/") { return true }
        // `Package.swift`: a name, a dot and a short extension of letters and digits.
        guard let dot = path.lastIndex(of: "."), dot != path.startIndex else { return false }
        let ext = path[path.index(after: dot)...]
        return (1 ... 10).contains(ext.count) && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
