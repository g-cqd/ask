/// Where the last segment of a row being converted ends, and whether it maps cell to grapheme (roadmap 0152): carried from run to run
/// so joining a run to it does not count its text again.
struct SegmentEnd {
    /// The column just past the segment's text.
    var column: Int
    /// Whether the segment draws as many graphemes as it shows.
    var isLinear: Bool
    /// Whether its text is all printable ASCII, a byte a grapheme and a column.
    var isASCII: Bool

    static func isPrintableASCII(_ text: String) -> Bool {
        let utf8 = text.utf8
        let bytes = utf8.span
        var index = 0
        while index < bytes.count, bytes[index] &- 0x20 < 0x5F { index += 1 }
        return index == bytes.count
    }
}
