internal import AemiRegex

/// UI projection of common literal shell heredocs, not a shell parser. Ambiguous/unsupported openers remain fully visible.
struct ShownToolInput: Sendable, Equatable {
    var text: String
    /// Input hard line to heredoc ordinal; the transcript offsets these by its tool header line.
    var toggles: [Int: Int] = [:]

    // Linear-time RE2 subset: no backreferences/lookaround or dependency on Swift Regex.
    private static let opener = try? Pattern(
        ##"^[\t ]*(?:cat|tee|python3?|ruby|bash|sh|zsh)(?:[\t ]+[^<'"#\n]*)?[\t ]*<<(-?)[\t ]*(?:'([A-Za-z_][A-Za-z0-9_]*)'|"([A-Za-z_][A-Za-z0-9_]*)"|([A-Za-z_][A-Za-z0-9_]*))[\t ]*(?:>[^;<|#\n]*)?$"##
    )

    init(_ source: String, isFolded: (Int) -> Bool) {
        text = source
        guard source.contains("<<"), let pattern = Self.opener else { return }
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var shown: [String] = []
        var index = 0
        var ordinal = 0
        while index < lines.count {
            let opening = lines[index]
            guard opening.contains("<<"), let match = pattern.firstMatch(in: opening),
                let group = (2 ... 4).compactMap({ match.range(ofGroup: $0, in: opening) }).first
            else {
                shown.append(String(opening))
                index += 1
                continue
            }
            let delimiter = opening[group]
            let stripsTabs = match.range(ofGroup: 1, in: opening).map { !opening[$0].isEmpty } ?? false
            guard
                let end = ((index + 1) ..< lines.count)
                    .first(where: {
                        (stripsTabs ? lines[$0].drop(while: { $0 == "\t" }) : lines[$0]) == delimiter
                    })
            else {
                // An unterminated literal heredoc owns the rest of the input. Keep it all visible in one pass.
                shown += lines[index...].map(String.init)
                break
            }
            let count = end - index - 1
            let openingLine = shown.count
            shown.append(String(opening))
            if count > 40, isFolded(ordinal) {
                shown += lines[(index + 1) ..< (index + 21)].map(String.init)
                toggles[shown.count] = ordinal
                shown.append("[… \(count - 20) lines embedded heredoc …]")
            } else {
                if count > 40 { toggles[openingLine] = ordinal }
                shown += lines[(index + 1) ..< end].map(String.init)
            }
            shown.append(String(lines[end]))
            ordinal += 1
            index = end + 1
        }
        text = shown.joined(separator: "\n")
    }
}
