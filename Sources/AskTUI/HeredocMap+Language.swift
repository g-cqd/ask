internal import AemiLexers
internal import AemiRegex

extension HeredocMap {
    /// A redirection target (`> path`, `>> path`, `>| path`), optionally quoted.
    private static let redirectTarget = try? Pattern(##">>?\|?[\t ]*(?:'([^'\n]+)'|"([^"\n]+)"|([^\s;|&<>()]+))"##)
    /// A `tee` target (`tee [-a] path`).
    private static let teeTarget = try? Pattern(
        ##"\btee(?:[\t ]+-[a-zA-Z]+)*[\t ]+(?:'([^'\n]+)'|"([^"\n]+)"|([^\s;|&<>()]+))"##
    )

    /// The simple-command clause (`;`, `&&`, `||`, `|`, `(` separated) containing `position`, walked in one pass.
    static func commandClause(in line: Substring, around position: Substring.Index) -> Substring {
        var start = line.startIndex
        var end = line.endIndex
        var inSingle = false
        var inDouble = false
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "'", !inDouble {
                inSingle.toggle()
            } else if ch == "\"", !inSingle {
                inDouble.toggle()
            } else if !inSingle, !inDouble {
                if index < position, ch == ";" || ch == "|" || ch == "&" || ch == "(" {
                    start = line.index(after: index)
                } else if index >= position, ch == ";" || ch == "|" || ch == "&" || ch == ")" {
                    end = index
                    break
                }
            }
            index = line.index(after: index)
        }
        return line[start ..< end]
    }

    /// Infers the body language from the command clause's program, any redirection target (`cat > Foo.swift`), or a `#!` first line.
    static func language(for spec: OpenerSpec, firstBodyLine: Substring) -> Language {
        let program = firstProgram(in: spec.clause)
        if let known = Self.interpreter(program) { return known }
        if program == "cat" || program == "tee" || program.isEmpty {
            let target =
                Self.capturedTarget(in: spec.clause, pattern: Self.redirectTarget)
                ?? (program == "tee" ? Self.capturedTarget(in: spec.clause, pattern: Self.teeTarget) : nil)
            if let target {
                let byPath = Language(path: String(target), firstLine: firstBodyLine)
                if byPath != .plain { return byPath }
            }
        }
        return Language(path: "script", firstLine: firstBodyLine)
    }

    /// The program basename of `clause`, skipping leading env assignments (`FOO=1`) and wrapper programs.
    private static func firstProgram(in clause: Substring) -> String {
        let words = clause.split(whereSeparator: { $0 == " " || $0 == "\t" })
        for word in words {
            if word.contains("="), !word.hasPrefix("=") { continue }
            if word.hasPrefix("<") || word.hasPrefix(">") { continue }
            let base = String(word.split(separator: "/").last ?? word)
            if Self.wrappers.contains(base) || base.hasPrefix("-") { continue }
            return base
        }
        return ""
    }

    private static func capturedTarget(in clause: Substring, pattern: Pattern?) -> Substring? {
        guard let pattern, let match = pattern.firstMatch(in: clause) else { return nil }
        for group in 1 ... 3 {
            if let range = match.range(ofGroup: group, in: clause) { return clause[range] }
        }
        return nil
    }

    private static let wrappers: Set<String> = ["env", "sudo", "command", "time", "nohup"]

    /// The language whose interpreter is `program`, when AemiLexers knows it.
    private static func interpreter(_ program: String) -> Language? {
        if program == "python" || program.hasPrefix("python3") { return .python }
        switch program {
            case "node": return .javascript
            case "deno", "bun": return .typescript
            case "ruby": return .ruby
            case "lua": return .lua
            case "swift": return .swift
            case "sh", "bash", "zsh", "dash", "ksh": return .shell
            case "fish": return .fish
            case "jq": return .json
            default: return nil
        }
    }
}
