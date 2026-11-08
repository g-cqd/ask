internal import AemiLexers

/// The part of a file tool's block that is a file's text, and the language it is coloured in (roadmap 0152, phase 3): what a `read`
/// returned, or what a `write` puts in the file.
struct FileCode: Sendable, Equatable {
    enum Part: Sendable, Equatable {
        case input, output
    }

    var part: Part
    var language: Language
    /// Hard lines of that text drawn as they are: the read's own notes, of the lines it shows and of the lines it did not keep.
    var plainLines: Set<Int> = []
    /// The hard line lexing starts afresh at: the first of a folded output's tail, which does not continue the head.
    var restart: Int?
    /// The diff the text is, each line led by its marker and lexed on its own side (roadmap 0152): an edit's, or a unified diff in a
    /// tool's output; nil for a file's own text.
    var diff: DiffLook.Format?
    /// The colours and links the output's own escapes asked for, by the shown text's hard line (note n30); when set, they are drawn
    /// instead of lexing `language`.
    var spans: [[OutputEscapes.Span]]?

    /// Whether `line` is a note ask or the `read` tool adds to a file's text, not a line of the file.
    static func isNote(_ line: Substring) -> Bool {
        (line.hasPrefix("[lines ") && line.hasSuffix("]"))
            || (line.hasPrefix("… ") && line.hasSuffix(" more lines not shown"))
    }
}
