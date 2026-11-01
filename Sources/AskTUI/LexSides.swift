internal import AemiLexers

/// The lexer states a text is scanned in, line by line (roadmap 0152): one for a file's text, or one for each side of an edit's diff,
/// whose removed lines continue the old text, added lines the new one, and kept lines both, so a comment one side opens does not run
/// into the other.
struct LexSides {
    private var old = LexState.initial
    private var new = LexState.initial

    /// Scans `line`, the code of a line of `kind`, into `tokens`, from the state its side ended the line before in.
    mutating func scan(
        _ line: Substring, kind: DiffLook.Kind, lexer: LexicalLineLexer, into tokens: inout [LineToken]
    ) {
        var bytes = line
        switch kind {
            case .removed: old = bytes.withUTF8 { lexer.scan($0.span, from: old, into: &tokens) }
            case .added: new = bytes.withUTF8 { lexer.scan($0.span, from: new, into: &tokens) }
            case .kept:
                let together = old == new
                new = bytes.withUTF8 { lexer.scan($0.span, from: new, into: &tokens) }
                guard !together else {
                    old = new
                    return
                }
                var ignored: [LineToken] = []
                old = bytes.withUTF8 { lexer.scan($0.span, from: old, into: &ignored) }
        }
    }
}
