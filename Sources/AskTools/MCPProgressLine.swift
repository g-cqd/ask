internal import AskMCP

/// A server's progress report as the short line a running block shows (roadmap 0067): the share done when the server gives a total,
/// then its words; with no total, its words, or else its count.
enum MCPProgressLine {
    /// The longest the server's words are kept, in characters, so the line fits beside a block's header.
    static let messageLimit = 48

    static func of(_ report: MCPProgress) -> String {
        let words = report.message.map(Self.words) ?? ""
        guard let total = report.total, total > 0 else {
            return words.isEmpty ? count(report.progress) : words
        }
        let share = Int(Swift.min(1, Swift.max(0, report.progress / total)) * 100)
        return words.isEmpty ? "\(share)%" : "\(share)% · \(words)"
    }

    /// The message on one line, its runs of white space made one space, cut to ``messageLimit`` with an ellipsis.
    private static func words(_ message: String) -> String {
        let line = message.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > messageLimit else { return line }
        return String(line.prefix(messageLimit - 1)) + "…"
    }

    /// A count as a whole number when it is one.
    private static func count(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
