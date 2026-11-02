internal import TerminalKitMarkdown
internal import TerminalKitStyle

extension ScreenComposer {
    /// TerminalKit's standard theme, with code blocks inside a dim rule (roadmap 0177, the owner's choice): the language on a `╭─` corner,
    /// `│` down the gutter, `╰─` after the code. The rule is chrome, so a copy is the code alone.
    static let markdownTheme: MarkdownTheme = {
        var theme = MarkdownTheme.standard
        theme.codeGutter = "│ "
        theme.codeOpen = "╭─ "
        theme.codeClose = "╰─"
        theme.codeRule = Style(dim: true)
        return theme
    }()
}
