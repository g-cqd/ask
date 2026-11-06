/// The first or last line of a text, read from its end without splitting the rest (note n47): a resumed session took the last line
/// of every tool's output, and splitting each whole output by `Character` for it cost seconds on a long session.
///
/// A line is what `split(separator: "\n")` gives, empty ones skipped, with a carriage return before its line feed left out.
public enum TextLines {
    /// The first line that is not empty, or nil when there is none.
    public static func first(of text: String) -> String? {
        let bytes = text.utf8
        var start = bytes.startIndex
        while start < bytes.endIndex {
            let end = bytes[start...].firstIndex(of: lineFeed) ?? bytes.endIndex
            if let line = line(in: text, from: start, to: end) { return line }
            guard end < bytes.endIndex else { return nil }
            start = bytes.index(after: end)
        }
        return nil
    }

    /// The last line that is not empty, or nil when there is none.
    public static func last(of text: String) -> String? {
        let bytes = text.utf8
        var end = bytes.endIndex
        while end > bytes.startIndex {
            let start = bytes[..<end].lastIndex(of: lineFeed).map(bytes.index(after:)) ?? bytes.startIndex
            if let line = line(in: text, from: start, to: end) { return line }
            guard start > bytes.startIndex else { return nil }
            end = bytes.index(before: start)
        }
        return nil
    }

    private static let lineFeed = UInt8(ascii: "\n")

    /// The text between two line boundaries, its closing carriage return left out; nil when that leaves nothing.
    private static func line(in text: String, from start: String.Index, to end: String.Index) -> String? {
        var end = end
        if end > start, text.utf8[text.utf8.index(before: end)] == UInt8(ascii: "\r") {
            end = text.utf8.index(before: end)
        }
        return end > start ? String(text[start ..< end]) : nil
    }
}
