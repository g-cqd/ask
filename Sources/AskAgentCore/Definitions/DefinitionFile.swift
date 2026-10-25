/// A definition file read for what it holds, never rejected for how it is written: a skill's `SKILL.md`, or an agent definition in any harness's format.
///
/// Reading cannot fail. It returns the fields it understood, the comments that look like `key: value`, the body, and a list of things it noticed;
/// a file that is not what it expected yields fewer fields and more diagnostics, never an error (roadmap 0061). The shapes it accepts are the
/// ones found in real harness directories: YAML or TOML fences, a bare TOML file, no head at all, quoted and block scalars, flow and block lists,
/// nested maps, comments, byte-order marks, CRLF, and keys spelled in any case or style.
public struct DefinitionFile: Sendable, Equatable {
    /// How the head was written.
    public enum Format: Sendable, Equatable {
        case yaml
        case toml
        /// No head: the whole text is the body.
        case none
    }

    public internal(set) var format = Format.none
    /// The keys, as written and in order. A key written twice appears once, with the last value, and the repeat is a diagnostic.
    public internal(set) var entries: [DefinitionEntry] = []
    /// Comments of the form `# key: value` or `# key = value`, which some harnesses use to carry a setting another harness would ignore
    /// (`# fallback_models: a, b`). Kept as entries; no one is told they are there unless they ask.
    public internal(set) var hints: [DefinitionEntry] = []
    /// What follows the head.
    public internal(set) var body = ""
    /// What was noticed and tolerated.
    public internal(set) var diagnostics: [String] = []

    /// Reads `text`. `isTOML` says the whole file is TOML, as Codex's and Vibe's agent files are (they have no fences).
    public init(parsing text: String, isTOML: Bool = false) {
        var lines = Self.lines(of: text)
        if isTOML {
            format = .toml
            let head = TOMLHead(lines: lines)
            (entries, hints, diagnostics) = (head.entries, head.hints, head.diagnostics)
            return
        }
        guard let open = lines.firstIndex(where: { !$0.allSatisfy(\.isWhitespace) }),
            let fence = Self.fence(lines[open])
        else {
            body = lines.joined(separator: "\n")
            return
        }
        lines.removeSubrange(..<open)
        let close = lines.dropFirst().firstIndex { Self.isClose($0, for: fence) }
        let end = close ?? Self.unterminatedEnd(lines)
        if close == nil {
            diagnostics.append("the opening \(fence) has no closing line; the head was read up to the first blank line")
        }
        let headLines = Array(lines[1 ..< Swift.max(1, end)])
        body = lines.dropFirst(close.map { $0 + 1 } ?? end).joined(separator: "\n")
        if fence == "+++" {
            format = .toml
            let head = TOMLHead(lines: headLines)
            (entries, hints, diagnostics) = (head.entries, head.hints, diagnostics + head.diagnostics)
        } else {
            format = .yaml
            let head = YAMLHead(lines: headLines)
            (entries, hints, diagnostics) = (head.entries, head.hints, diagnostics + head.diagnostics)
        }
    }

    /// Lines with the byte-order mark gone and every kind of line ending read as one.
    static func lines(of text: String) -> [String] {
        var text = Substring(text)
        if text.first == "\u{FEFF}" { text = text.dropFirst() }
        return text.replacing("\r\n", with: "\n").replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func fence(_ line: String) -> String? {
        let trimmed = line.trimmingTrailingWhitespace()
        return trimmed == "---" || trimmed == "+++" ? trimmed : nil
    }

    private static func isClose(_ line: String, for fence: String) -> Bool {
        let trimmed = line.trimmingTrailingWhitespace()
        return trimmed == fence || (fence == "---" && trimmed == "...")
    }

    /// Where a head with no closing fence is taken to end: its first blank line.
    private static func unterminatedEnd(_ lines: [String]) -> Int {
        lines.dropFirst().firstIndex { $0.allSatisfy(\.isWhitespace) } ?? lines.count
    }
}
