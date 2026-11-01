internal import AemiLexers

extension Transcript {
    /// What of the tool block at `index` is a file's text and its language, with highlighting on (roadmap 0152, phase 3): a `read`'s
    /// output and a `write`'s content, by the path the call names, then a `#!` line for a name without an extension. Nil for any other
    /// tool, a failed call, or a language the lexers do not know, which draws plain.
    func fileCode(at index: Int) -> FileCode? {
        guard highlight, let path = toolPaths[index],
            case .tool(let name, _, let status, let output, let input) = items[index]
        else { return nil }
        if case .failed = status { return nil }
        switch name {
            case "write":
                return Self.language(of: path, text: input).map { FileCode(part: .input, language: $0) }
            case "read":
                guard let language = Self.language(of: path, text: output) else { return nil }
                let shown = shownToolOutput(at: index)
                let text = shown?.text ?? output
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                let notes = lines.indices.suffix(2).filter { FileCode.isNote(lines[$0]) }
                return FileCode(
                    part: .output, language: language, plainLines: Set(notes),
                    restart: shown?.folded == true ? shown?.markerLine : nil)
            default: return nil
        }
    }

    /// The language of the file at `path` whose text starts as `text` does; nil when it is plain.
    private static func language(of path: String, text: String) -> Language? {
        let language = Language(path: path, firstLine: text.split(separator: "\n", maxSplits: 1).first)
        return language == .plain ? nil : language
    }
}
