internal import AemiLexers
internal import TerminalKitMarkdown
internal import TerminalKitStyle

/// Fenced code coloured by aemi's lexers (roadmap 0152, phase 2; `ui.highlight`): the fence's first word names the language, each line is
/// lexed from the state the line before it ended in, and each token's role takes a colour of the terminal's own palette, so the colours
/// follow its theme and the system appearance with it. A language the lexers do not know is drawn plain, never as another.
struct CodeHighlighter: MarkdownCodeHighlighter {
    static let standard = CodeHighlighter()

    func highlight(_ lines: [String], language: String) -> [[MarkdownHighlight]]? {
        guard let language = Language(name: language), language != .plain else { return nil }
        let lexer = LexicalLineLexer(language: language)
        var state = LexState.initial
        var tokens: [LineToken] = []
        var result: [[MarkdownHighlight]] = []
        result.reserveCapacity(lines.count)
        for line in lines {
            tokens.removeAll(keepingCapacity: true)
            state = lexer.scan(line.utf8.span, from: state, into: &tokens)
            result.append(
                tokens.compactMap { token in Self.style(of: token.role).map { .init(bytes: token.range, style: $0) } })
        }
        return result
    }

    /// The colour of `role`, or of the nearest role above it that has one; nil leaves the code style.
    static func style(of role: HighlightRole) -> Style? {
        var role: HighlightRole? = role
        while let current = role {
            if let style = styles[current] { return style }
            role = current.parent
        }
        return nil
    }

    /// The roles the scanners give, in the palette's eight colours: the terminal's theme decides what each looks like.
    private static let styles: [HighlightRole: Style] = [
        .keyword: Style(fg: .indexed(5)), .string: Style(fg: .indexed(2)), .comment: Style(dim: true, italic: true),
        .number: Style(fg: .indexed(3)), .type: Style(fg: .indexed(6)), .attribute: Style(fg: .indexed(4)),
        .tag: Style(fg: .indexed(4)), .property: Style(fg: .indexed(6)), .escape: Style(fg: .indexed(3))
    ]
}
