/// A tool's output with its middle folded away when it is longer than the screen should show at once (roadmap 0078): the head
/// and the tail share the budget, each taking half the lines and half the bytes, the head the odd line. Open, the whole output is
/// shown and the marker stays where the middle starts, so a click folds it again. Whole lines only: a line too large for either end
/// is hidden whole. The marker is drawn between the two ends as a row of its own, never part of the text a selection copies.
struct ShownToolOutput: Sendable, Equatable {
    /// What the block shows: the head and the tail when folded, the whole output when open or short.
    var text: String
    /// The shown text's hard line the marker goes before; nil when the output fits both limits.
    var markerLine: Int?
    /// The lines of the middle, and their UTF-8 bytes, each counted with its line feed.
    var hiddenLines = 0
    var hiddenBytes = 0
    var folded: Bool

    init(_ output: String, maxLines: Int, maxBytes: Int, folded: Bool) {
        self.text = output
        self.folded = folded
        guard TranscriptContent.hardLineCount(of: output) > maxLines || output.utf8.count > maxBytes else { return }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let head = Self.fitting(lines, lines: (maxLines + 1) / 2, bytes: maxBytes / 2)
        let tail = Self.fitting(lines[head...].reversed(), lines: maxLines / 2, bytes: maxBytes / 2)
        let middle = lines[head ..< (lines.count - tail)]
        markerLine = head
        hiddenLines = middle.count
        hiddenBytes = middle.reduce(0) { $0 + $1.utf8.count + 1 }
        if folded { text = (lines[..<head] + lines[(lines.count - tail)...]).joined(separator: "\n") }
    }

    /// The row drawn between the two ends.
    var marker: String {
        let lines = "\(hiddenLines) line\(hiddenLines == 1 ? "" : "s")"
        return folded
            ? "⋯ \(lines) hidden (\(Self.size(hiddenBytes))) · click to show" : "⋯ \(lines) shown · click to fold"
    }

    /// How many of `lines`, from the first, fit both `lines` and `bytes` (each line counted with its line feed).
    private static func fitting(_ candidates: some Sequence<Substring>, lines: Int, bytes: Int) -> Int {
        var taken = 0
        var used = 0
        for line in candidates {
            guard taken < lines, used + line.utf8.count + 1 <= bytes else { break }
            taken += 1
            used += line.utf8.count + 1
        }
        return taken
    }

    /// A size for a glance: bytes below 1 KiB, else the largest IEC unit, rounded to a whole number.
    static func size(_ bytes: Int) -> String {
        var value = Double(bytes)
        for unit in ["B", "KiB", "MiB"] {
            if value.rounded() < 1024 { return "\(Int(value.rounded())) \(unit)" }
            value /= 1024
        }
        return "\(Int(value.rounded())) GiB"
    }
}
