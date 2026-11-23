internal import AemiLexers
internal import AemiRegex
internal import Foundation

/// Where each heredoc body lies in a bash command, and which language it is in (t128): read from the command lines as shown
/// (so folded heredoc placeholders stay plain and do not confuse the language lexer).
///
/// The language comes from: (1) the interpreter reading the heredoc (`python3 - <<'EOF'`, `node <<EOF`, `ruby`, `swift`, `sh`);
/// (2) the file written when `cat` or `tee` directs to one (`cat > Foo.swift <<'EOF'`); (3) a `#!` line at the top of the body;
/// else plain text.
struct HeredocMap {
    struct Body: Equatable {
        /// Hard line indices within the command (0-based), exclusive of the opener and closing delimiter.
        let lines: Range<Int>
        let language: Language
        /// Whether `$var` / `$(…)` are expanded by the shell inside this body (`<<EOF`, not `<<'EOF'` or `<<"EOF"`).
        let expands: Bool
        /// A fold placeholder line inside `lines`, if `ShownToolInput` folded the middle of this heredoc.
        let placeholder: Int?
    }

    struct OpenerSpec {
        let delimiter: Substring
        let stripsTabs: Bool
        let quoted: Bool
        let clause: Substring
    }

    let bodies: [Body]
    /// For each hard line (0-based), the body index it belongs to, or nil.
    let bodyAtLine: [Int?]
    /// Closing delimiter line indices, so they are highlighted as plain/shell delimiters, not body.
    let closers: Set<Int>

    /// Matches each `<<` / `<<-` heredoc opener on a line, capturing strip-tabs (`-`), quote (`'` or `"`), and delimiter word.
    private static let opener = try? Pattern(
        ##"(?:^|[^<])<<(-?)[\t ]*(?:(?:'([A-Za-z_][A-Za-z0-9_]*)')|(?:"([A-Za-z_][A-Za-z0-9_]*)")|(?:(\\?)([A-Za-z_][A-Za-z0-9_]*)))"##
    )
    /// A fold placeholder inserted by `ShownToolInput`.
    private static let foldMarker = try? Pattern(##"^\[… \d+ lines embedded heredoc …\]$"##)

    /// Maps all heredocs in `command` (the shown command text, hard lines separated by `\n`).
    init(_ command: String) {
        guard command.utf8.contains(0x3C), command.contains("<<"), let opener = Self.opener else {
            bodies = []
            bodyAtLine = []
            closers = []
            return
        }
        let lines = command.split(separator: "\n", omittingEmptySubsequences: false)
        var bodies: [Body] = []
        var bodyAtLine = [Int?](repeating: nil, count: lines.count)
        var closers: Set<Int> = []
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let found = Self.openers(in: line, pattern: opener)
            lineIndex += 1
            guard !found.isEmpty else { continue }
            for spec in found {
                let start = lineIndex
                var placeholder: Int?
                var end: Int?
                var scan = start
                while scan < lines.count {
                    let candidate = spec.stripsTabs ? lines[scan].drop(while: { $0 == "\t" }) : lines[scan]
                    if candidate == spec.delimiter {
                        end = scan
                        break
                    }
                    if placeholder == nil, lines[scan].hasPrefix("[… "), let marker = Self.foldMarker,
                        marker.firstMatch(in: lines[scan]) != nil
                    {
                        placeholder = scan
                    }
                    scan += 1
                }
                let bodyEnd = end ?? lines.count
                if bodyEnd > start {
                    let firstLine = spec.stripsTabs ? lines[start].drop(while: { $0 == "\t" }) : lines[start]
                    let language = Self.language(for: spec, firstBodyLine: firstLine)
                    let bodyIndex = bodies.count
                    bodies.append(
                        Body(
                            lines: start ..< bodyEnd,
                            language: language,
                            expands: !spec.quoted,
                            placeholder: placeholder
                        )
                    )
                    for row in start ..< bodyEnd { bodyAtLine[row] = bodyIndex }
                }
                guard let end else {
                    lineIndex = lines.count
                    break
                }
                closers.insert(end)
                lineIndex = end + 1
            }
        }
        self.bodies = bodies
        self.bodyAtLine = bodyAtLine
        self.closers = closers
    }

    /// All heredoc openers on `line`, left to right, skipping any inside quotes, `#` comments, or `<<<` here-strings.
    private static func openers(in line: Substring, pattern: Pattern) -> [OpenerSpec] {
        guard line.utf8.contains(0x3C), line.contains("<<") else { return [] }
        let code = unquotedPrefixBeforeComment(line)
        var result: [OpenerSpec] = []
        var cursor = code.startIndex
        while cursor < code.endIndex {
            let tail = code[cursor...]
            guard let match = pattern.firstMatch(in: tail) else { break }
            let fullRange = match.range(in: tail)
            let matchStart = fullRange.lowerBound
            if !isInsideQuotes(line, before: matchStart) {
                let stripsTabs = match.range(ofGroup: 1, in: tail).map { !tail[$0].isEmpty } ?? false
                let single = match.range(ofGroup: 2, in: tail)
                let double = match.range(ofGroup: 3, in: tail)
                let escaped = match.range(ofGroup: 4, in: tail).map { !tail[$0].isEmpty } ?? false
                let bare = match.range(ofGroup: 5, in: tail)
                if let range = single ?? double ?? bare {
                    let clause = commandClause(in: code, around: matchStart)
                    result.append(
                        OpenerSpec(
                            delimiter: tail[range],
                            stripsTabs: stripsTabs,
                            quoted: single != nil || double != nil || escaped,
                            clause: clause
                        )
                    )
                }
            }
            cursor = fullRange.upperBound
        }
        return result
    }

    /// Walks `line` up to `limit`, tracking shell single/double quotes and backslashes; when `stopAtComment` is true, stops at
    /// an unquoted `#` that begins a shell comment. Returns `(endIndex, inQuotes)`.
    static func scanQuotes(in line: Substring, upTo limit: Substring.Index, stopAtComment: Bool) -> (
        end: Substring.Index, inQuotes: Bool
    ) {
        var inSingle = false
        var inDouble = false
        var escaped = false
        var previousIsSpace = true
        var index = line.startIndex
        while index < limit {
            let ch = line[index]
            if escaped {
                escaped = false
            } else if ch == "\\", !inSingle {
                escaped = true
            } else if ch == "'", !inDouble {
                inSingle.toggle()
            } else if ch == "\"", !inSingle {
                inDouble.toggle()
            } else if stopAtComment, ch == "#", !inSingle, !inDouble, previousIsSpace {
                return (index, false)
            }
            previousIsSpace = ch == " " || ch == "\t" || ch == ";" || ch == "("
            index = line.index(after: index)
        }
        return (limit, inSingle || inDouble)
    }

    private static func unquotedPrefixBeforeComment(_ line: Substring) -> Substring {
        line[..<scanQuotes(in: line, upTo: line.endIndex, stopAtComment: true).end]
    }

    private static func isInsideQuotes(_ line: Substring, before target: Substring.Index) -> Bool {
        scanQuotes(in: line, upTo: target, stopAtComment: false).inQuotes
    }
}
