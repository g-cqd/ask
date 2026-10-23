/// A fenced code block in Markdown text, located by hard line (CommonMark's fences: up to three spaces of indent, then three or more
/// backticks or tildes; a closing fence uses the same character, at least as many, and nothing after it).
struct CodeFence: Sendable, Equatable {
    /// The hard line of the opening fence.
    var openingLine: Int
    /// The closing fence's hard line, or the text's last line when the block has not closed (streaming, or never closed).
    var lastLine: Int
    /// The first word of the info string, such as `swift`; empty when there is none.
    var language: String
    var isClosed: Bool

    /// The lines between the fences: what the block holds.
    var bodyLines: Int { isClosed ? lastLine - openingLine - 1 : lastLine - openingLine }

    /// Every fenced block in `lines`, in order.
    /// - Complexity: O(n) in the characters of `lines`.
    static func scan(_ lines: [Substring]) -> [CodeFence] {
        var fences: [CodeFence] = []
        struct Open {
            var line: Int
            var marker: Character
            var length: Int
            var language: String
        }
        var open: Open?
        for (index, line) in lines.enumerated() {
            guard let fence = marker(line) else { continue }
            if let current = open {
                if fence.marker == current.marker, fence.length >= current.length, fence.info.isEmpty {
                    fences.append(
                        CodeFence(
                            openingLine: current.line, lastLine: index, language: current.language, isClosed: true))
                    open = nil
                }
            } else if fence.marker == "~" || !fence.info.contains("`") {
                let language = fence.info.prefix { $0 != " " && $0 != "\t" }
                open = Open(line: index, marker: fence.marker, length: fence.length, language: String(language))
            }
        }
        if let current = open {
            fences.append(
                CodeFence(
                    openingLine: current.line, lastLine: Swift.max(current.line, lines.count - 1),
                    language: current.language, isClosed: false))
        }
        return fences
    }

    /// The fence on a line, with its character, its length and the info string after it, trimmed.
    private static func marker(_ line: Substring) -> (marker: Character, length: Int, info: Substring)? {
        var rest = line
        var indent = 0
        while rest.first == " " {
            indent += 1
            guard indent <= 3 else { return nil }
            rest = rest.dropFirst()
        }
        guard let first = rest.first, first == "`" || first == "~" else { return nil }
        let length = rest.prefix { $0 == first }.count
        guard length >= 3 else { return nil }
        var info = rest.dropFirst(length).drop { $0 == " " || $0 == "\t" }
        while let last = info.last, last == " " || last == "\t" || last == "\r" { info = info.dropLast() }
        return (first, length, info)
    }
}
