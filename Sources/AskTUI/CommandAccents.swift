internal import AemiLexers
internal import TerminalKitStyle
internal import TerminalKitText

/// Syntax highlighting for an open command block's command lines and its embedded heredocs (t128): shell lines are lexed as
/// `.shell` (keeping state across continuations, reset across heredoc bodies), and each heredoc body is lexed in the language
/// `HeredocMap` inferred for it (`python3`, `cat > Foo.swift`, `#!`). Every token keeps full brightness over `commandStyle`,
/// except comments (dim italic) and fold placeholders (dim).
struct CommandAccents {
    private struct LexedRow {
        let text: Substring
        let ascii: Bool
        let tokens: [(bytes: Range<Int>, style: Style)]
    }

    private var rows: [LexedRow] = []
    /// Character count of the `shell · … · ` lead before the command on hard line 0.
    private let leadCharacters: Int
    private var walk = (line: -1, offset: 0, byte: 0)

    /// Lexes `command` (the shown command text, without the block's lead) with heredoc bodies in their own languages.
    /// `lead` is the prefix before `command` on hard line 0 (`shell · ` or `shell · timeout 5 sec · `).
    init(command: String, lead: String) {
        leadCharacters = lead.count
        // Parse heredocs on the raw command so `<<-` tab-stripping sees real tabs before they expand to 4 spaces.
        let map = HeredocMap(command)
        let wrapped = command.utf8.contains(0x09) ? command.replacing("\t", with: "    ") : command
        let rawLines = wrapped.split(separator: "\n", omittingEmptySubsequences: false)
        let shellLexer = LexicalLineLexer(language: .shell)
        var shellState = LexState.initial
        var bodyLexers: [(lexer: LexicalLineLexer, state: LexState)?] = map.bodies.map {
            $0.language == .plain ? nil : (LexicalLineLexer(language: $0.language), .initial)
        }
        var tokens: [LineToken] = []
        rows.reserveCapacity(rawLines.count)

        for (index, line) in rawLines.enumerated() {
            if index < map.bodyAtLine.count, let bodyIndex = map.bodyAtLine[index] {
                let body = map.bodies[bodyIndex]
                if body.placeholder == index {
                    rows.append(LexedRow(text: line, ascii: true, tokens: [(0 ..< line.utf8.count, Style(dim: true))]))
                    // After a folded middle the body's lexer starts fresh rather than carrying stale state across hidden lines.
                    bodyLexers[bodyIndex]?.state = .initial
                    continue
                }
                if let entry = bodyLexers[bodyIndex] {
                    tokens.removeAll(keepingCapacity: true)
                    let next = entry.lexer.scan(line.utf8.span, from: entry.state, into: &tokens)
                    bodyLexers[bodyIndex] = (entry.lexer, next)
                    let styled = Self.styled(tokens)
                    rows.append(LexedRow(text: line, ascii: line.utf8.allSatisfy { $0 < 0x80 }, tokens: styled))
                } else if body.expands {
                    // An unquoted heredoc of unknown language still expands `$var` / `${…}` in the shell.
                    rows.append(
                        LexedRow(
                            text: line,
                            ascii: line.utf8.allSatisfy { $0 < 0x80 },
                            tokens: Self.expansionTokens(in: line)
                        )
                    )
                } else {
                    rows.append(LexedRow(text: line, ascii: true, tokens: []))
                }
            } else if map.closers.contains(index) {
                // Closing delimiter: dimmed slightly or styled as a keyword/delimiter? Keep bright, keyword accent on the word.
                let trimmed = line.drop(while: { $0 == " " })
                let start = line.utf8.distance(from: line.startIndex, to: trimmed.startIndex)
                let range = start ..< line.utf8.count
                let styled: [(Range<Int>, Style)] =
                    range.isEmpty ? [] : [(range, CodeHighlighter.style(of: .keyword) ?? Style())]
                rows.append(LexedRow(text: line, ascii: line.utf8.allSatisfy { $0 < 0x80 }, tokens: styled))
            } else {
                tokens.removeAll(keepingCapacity: true)
                shellState = shellLexer.scan(line.utf8.span, from: shellState, into: &tokens)
                rows.append(
                    LexedRow(text: line, ascii: line.utf8.allSatisfy { $0 < 0x80 }, tokens: Self.styled(tokens))
                )
            }
        }
    }

    /// Applies syntax accents to `line` (a row of the open command block), keeping the lead dim on line 0 and every command token
    /// at full brightness over `ScreenComposer.commandStyle`.
    mutating func applying(to line: ScreenComposer.Line, block: Int, commandLines: Int) -> ScreenComposer.Line {
        guard let source = line.source, source.block == block, source.line < commandLines,
            rows.indices.contains(source.line)
        else { return line }
        var line = line
        // On hard line 0, rows that still contain part of the lead keep the dim lead and brighten only the command portion.
        let isLeadRow = source.line == 0 && source.offset < leadCharacters
        if !isLeadRow { line.style = ScreenComposer.commandStyle }
        let commandCharOffset: Int
        let rowStartCol: Int
        let shownCommand: String
        if isLeadRow {
            let skipChars = leadCharacters - source.offset
            let leadShown = String(source.text.prefix(skipChars))
            shownCommand = String(source.text.dropFirst(skipChars))
            rowStartCol = source.col + UnicodeWidth.displayWidth(of: leadShown)
            commandCharOffset = 0
        } else if source.line == 0 {
            shownCommand = source.text
            rowStartCol = source.col
            commandCharOffset = source.offset - leadCharacters
        } else {
            shownCommand = source.text
            rowStartCol = source.col
            commandCharOffset = source.offset
        }
        guard !shownCommand.isEmpty else { return line }
        let entry = rows[source.line]
        let startByte = CodeAccents.byte(
            at: source.line,
            offset: commandCharOffset,
            text: entry.text,
            ascii: entry.ascii,
            cursor: &walk
        )
        let endByte = startByte + shownCommand.utf8.count
        let columns = CodeAccents.columns(of: shownCommand)
        let totalEndCol = rowStartCol + columns(shownCommand.utf8.count)
        let lineTokens = rows[source.line].tokens
        var accents: [ScreenComposer.Accent] = []
        var covered = rowStartCol
        for token in lineTokens where token.bytes.overlaps(startByte ..< endByte) {
            let low = rowStartCol + columns(Swift.max(token.bytes.lowerBound, startByte) - startByte)
            let high = rowStartCol + columns(Swift.min(token.bytes.upperBound, endByte) - startByte)
            guard high > low else { continue }
            if isLeadRow, low > covered {
                accents.append(ScreenComposer.Accent(columns: covered ..< low, style: ScreenComposer.commandStyle))
            }
            accents.append(ScreenComposer.Accent(columns: low ..< high, style: token.style))
            covered = Swift.max(covered, high)
        }
        if isLeadRow, covered < totalEndCol {
            accents.append(ScreenComposer.Accent(columns: covered ..< totalEndCol, style: ScreenComposer.commandStyle))
        }
        line.accents += accents
        return line
    }

    private static func styled(_ tokens: [LineToken]) -> [(bytes: Range<Int>, style: Style)] {
        tokens.compactMap { token in CodeHighlighter.style(of: token.role).map { (token.range, $0) } }
    }

    /// `$name` and `${…}` spans inside an unquoted heredoc whose body has no known language.
    private static func expansionTokens(in line: Substring) -> [(bytes: Range<Int>, style: Style)] {
        guard let style = CodeHighlighter.style(of: .attribute) else { return [] }
        let bytes = Array(line.utf8)
        var result: [(Range<Int>, Style)] = []
        var i = 0
        while i < bytes.count {
            if bytes[i] == 0x5C {
                i += 2
                continue
            }
            guard bytes[i] == 0x24, i + 1 < bytes.count else {
                i += 1
                continue
            }
            let start = i
            let next = bytes[i + 1]
            if next == 0x7B {
                // ${...}
                i += 2
                while i < bytes.count, bytes[i] != 0x7D { i += 1 }
                if i < bytes.count { i += 1 }
                result.append((start ..< i, style))
            } else if (next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A) || next == 0x5F {
                i += 2
                while i < bytes.count,
                    (bytes[i] >= 0x41 && bytes[i] <= 0x5A) || (bytes[i] >= 0x61 && bytes[i] <= 0x7A)
                        || (bytes[i] >= 0x30 && bytes[i] <= 0x39) || bytes[i] == 0x5F
                {
                    i += 1
                }
                result.append((start ..< i, style))
            } else {
                i += 1
            }
        }
        return result
    }
}
