/// A configuration file's bytes as the `/config` editor reads them to change one part and keep the rest (roadmap 0170): where its
/// lines start, how they are indented, and where the next byte that is not white space or a JSON5 comment is.
struct ConfigSourceText: Sendable {
    let bytes: [UInt8]

    private static let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t"), newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r"), slash = UInt8(ascii: "/"), star = UInt8(ascii: "*")

    /// The offset of the first byte of the line `offset` is on.
    func lineStart(_ offset: Int) -> Int {
        var start = Swift.min(offset, bytes.count)
        while start > 0, bytes[start - 1] != Self.newline { start -= 1 }
        return start
    }

    /// The spaces and tabs the line `offset` is on starts with.
    func indentation(atLineOf offset: Int) -> String {
        let start = lineStart(offset)
        let end = bytes[start...].firstIndex { $0 != Self.space && $0 != Self.tab } ?? bytes.count
        return String(decoding: bytes[start ..< end], as: UTF8.self)
    }

    /// Whether only spaces and tabs come before `offset` on its line.
    func startsLine(_ offset: Int) -> Bool {
        bytes[lineStart(offset) ..< offset].allSatisfy { $0 == Self.space || $0 == Self.tab }
    }

    /// The offset of the first byte at or after `offset` that is not white space or inside a comment.
    func significant(from offset: Int) -> Int {
        var index = offset
        while index < bytes.count {
            let byte = bytes[index]
            if byte == Self.space || byte == Self.tab || byte == Self.newline || byte == Self.carriageReturn {
                index += 1
            } else if byte == Self.slash, index + 1 < bytes.count, bytes[index + 1] == Self.slash {
                index = bytes[index...].firstIndex(of: Self.newline) ?? bytes.count
            } else if byte == Self.slash, index + 1 < bytes.count, bytes[index + 1] == Self.star {
                index = blockCommentEnd(from: index + 2)
            } else {
                return index
            }
        }
        return index
    }

    /// Just past the `*/` that ends a block comment whose body starts at `offset`.
    private func blockCommentEnd(from offset: Int) -> Int {
        var index = offset
        while index + 1 < bytes.count, !(bytes[index] == Self.star && bytes[index + 1] == Self.slash) { index += 1 }
        return Swift.min(index + 2, bytes.count)
    }

    /// Just past the end of the line `offset` is on, when nothing but spaces, tabs or a `//` comment follows it there; nil when
    /// something else does.
    func restOfLineEnd(from offset: Int) -> Int? {
        var index = offset
        while index < bytes.count, bytes[index] == Self.space || bytes[index] == Self.tab { index += 1 }
        if index + 1 < bytes.count, bytes[index] == Self.slash, bytes[index + 1] == Self.slash {
            index = bytes[index...].firstIndex(of: Self.newline) ?? bytes.count
        }
        if index < bytes.count, bytes[index] == Self.carriageReturn { index += 1 }
        guard index == bytes.count || bytes[index] == Self.newline else { return nil }
        return Swift.min(index + 1, bytes.count)
    }

    /// The start of the comment-only lines right above the line that starts at `start`, or `start` when there are none: the note
    /// a person wrote over a setting goes with it.
    func commentLinesAbove(_ start: Int) -> Int {
        var top = start
        while top > 0 {
            let above = lineStart(top - 1)
            let line = bytes[above ..< top - 1].drop { $0 == Self.space || $0 == Self.tab }
            let isComment =
                line.starts(with: [Self.slash, Self.slash])
                || (line.starts(with: [Self.slash, Self.star])
                    && line.reversed().drop { $0 == Self.carriageReturn }
                        .starts(with: [Self.slash, Self.star]))
            guard isComment else { break }
            top = above
        }
        return top
    }
}
