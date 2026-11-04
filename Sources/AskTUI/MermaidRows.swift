internal import AemiMarkdown
internal import AemiMermaidLayout
internal import AemiMermaidScene
internal import AemiMermaidSyntax
internal import AemiMermaidText
internal import TerminalKitMarkdown
internal import TerminalKitStyle
internal import TerminalKitText

/// A fenced block whose language is `mermaid`, drawn as the diagram it describes (roadmap 0198): the engine reads it within the terminal limits, lays it out no wider than the
/// transcript, and draws it in cells; each run of the result takes the style of its role in the theme. What the engine cannot draw, or has not got all of yet, stays the code block
/// it is: the caller draws it as it always did.
enum MermaidRows {
    /// The diagram in the top-level `block`, as rows no wider than `width`; nil if the block is not a closed mermaid fence or cannot be drawn in that width.
    static func rows(of block: MarkdownBlock, in document: MarkdownDocument, width: Int, theme: MarkdownTheme)
        -> [StyledLine]?
    {
        guard let source = diagram(of: block, in: document) else { return nil }
        let parse = MermaidParse.parse(source, limits: .terminal)
        var scene = DiagramScene()
        if case .refused = parse.result { return nil }
        let metrics = MermaidMetrics(columns: { Swift.max(0, UnicodeWidth.displayWidth(of: Character($0))) })
        let outcome = MermaidLayout.lay(parse.result, metrics: metrics, maxWidth: width, into: &scene)
        guard case .drawn = outcome, let rows = TextRenderer(metrics: metrics).rows(scene) else { return nil }
        return rows.map { row in StyledLine(row.map { StyledRun($0.text, style: style(of: $0.role, theme: theme)) }) }
    }

    /// The code of a closed mermaid fence: its lines, joined by line feeds. Nil for any other block, and for a fence that is still open: a diagram is read once, when its
    /// fence closes, so a streamed one is code until then.
    private static func diagram(of block: MarkdownBlock, in document: MarkdownDocument) -> [UInt8]? {
        var reader = MarkdownFenceReader()
        guard let header = reader.read(block, in: document), header.style != .indented, header.isClosed == true else {
            return nil
        }
        let language = document.source[header.language]
        guard language.count == 7, language.map({ $0 | 0x20 }).elementsEqual("mermaid".utf8) else { return nil }
        var code: [UInt8] = []
        for (index, line) in reader.lines.enumerated() {
            if index > 0 { code.append(0x0A) }
            code.append(contentsOf: document.source[line.range])
        }
        return code
    }

    /// The theme's style for a role: the text's own for nodes, the rule's for lines and frames, the quote's for notes.
    static func style(of role: SceneRole?, theme: MarkdownTheme) -> Style {
        switch role {
            case .none, .node?, .nodeAlt?, .labelBackground?, .danger?: theme.text
            case .edge?, .edgeAlt?, .cluster?, .muted?: theme.rule
            case .label?: theme.emphasis
            case .clusterTitle?: theme.strong
            case .note?: theme.quote
            case .activation?, .accent0?, .accent1?, .accent2?, .accent3?, .accent4?, .accent5?, .accent6?, .accent7?:
                theme.marker
        }
    }
}
