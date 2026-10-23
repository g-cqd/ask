/// What an assistant message shows: its text, with each folded long code block replaced by one placeholder line (ADR-0044: nothing is
/// hidden without a placeholder).
struct ShownCode: Sendable, Equatable {
    /// The text drawn and selected.
    var text: String
    /// Display hard line to the fence it toggles: a folded block's placeholder, or an open long block's opening fence.
    var toggles: [Int: Int] = [:]
    /// Display hard lines that are placeholders, drawn dim.
    var placeholders: Set<Int> = []

    /// - Parameters:
    ///   - source: The message as the model wrote it.
    ///   - limit: A block with more lines than this can fold.
    ///   - isFolded: Whether the long block with this ordinal is folded.
    /// - Complexity: O(n) in the characters of `source`; a message without a fence marker is returned as it is after one search.
    init(_ source: String, longerThan limit: Int, isFolded: (Int) -> Bool) {
        guard Self.mayContainFence(source) else {
            text = source
            return
        }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var shown: [Substring] = []
        shown.reserveCapacity(lines.count)
        var next = 0
        for (ordinal, fence) in CodeFence.scan(lines).enumerated() where fence.bodyLines > limit {
            shown += lines[next ..< fence.openingLine]
            toggles[shown.count] = ordinal
            if isFolded(ordinal) {
                placeholders.insert(shown.count)
                shown.append(Substring(Self.placeholder(for: fence)))
                next = fence.lastLine + 1
            } else {
                next = fence.openingLine
            }
        }
        shown += lines[next...]
        text = shown.joined(separator: "\n")
    }

    /// Whether `source` holds three backticks or three tildes in a row: one pass over its bytes, so a message with no code costs almost
    /// nothing. A `true` is only a maybe (an indented or inline run still counts); `CodeFence.scan` decides.
    /// - Complexity: O(n) in the bytes of `source`, no allocation.
    static func mayContainFence(_ source: String) -> Bool {
        var source = source
        return source.withUTF8 { bytes in
            var run = 0
            var last: UInt8 = 0
            for byte in bytes {
                if byte == last, byte == 0x60 || byte == 0x7E {
                    run += 1
                    if run == 3 { return true }
                } else {
                    last = byte
                    run = byte == 0x60 || byte == 0x7E ? 1 : 0
                }
            }
            return false
        }
    }

    /// `code · swift · 34 lines`, or `code · 34 lines` without a language.
    static func placeholder(for fence: CodeFence) -> String {
        let count = fence.bodyLines
        return
            (["code"] + (fence.language.isEmpty ? [] : [fence.language]) + ["\(count) \(count == 1 ? "line" : "lines")"])
            .joined(separator: " · ")
    }
}
