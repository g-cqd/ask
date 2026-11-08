internal import AemiLexers

extension Transcript {
    /// What of the tool block at `index` is a file's text and its language, with highlighting on (roadmap 0152, phase 3): a `read`'s
    /// output and a `write`'s content, by the path the call names, then a `#!` line for a name without an extension. Nil for any other
    /// tool, a failed call, or a language the lexers do not know, which draws plain.
    func fileCode(at index: Int) -> FileCode? {
        guard case .tool(let name, _, let status, let output, let input) = items[index] else { return nil }
        // The program's own colours (note n30), whatever `highlight` says; a file tool's input keeps its language.
        if let spans = outputSpans[index], toolPaths[index] == nil || !["write", "edit"].contains(name) {
            return FileCode(part: .output, language: .plain, spans: shownSpans(spans, at: index))
        }
        guard highlight else { return nil }
        guard let path = toolPaths[index] else {
            // Output still arriving is not recognised: it is incomplete, and it changes with every chunk.
            if case .running = status { return nil }
            return recognisedCode(at: index, output: output)
        }
        if case .failed = status { return nil }
        switch name {
            case "write":
                return Self.language(of: path, text: input).map { FileCode(part: .input, language: $0) }
            case "edit":
                return Self.language(of: path, text: "").map { FileCode(part: .input, language: $0, diff: .edit) }
            case "read":
                guard let language = Self.language(of: path, text: output) else { return nil }
                let shown = shownToolOutput(at: index)
                let text = shown?.text ?? output
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                let notes = lines.indices.suffix(2).filter { FileCode.isNote(lines[$0]) }
                return FileCode(
                    part: .output,
                    language: language,
                    plainLines: Set(notes),
                    restart: shown?.folded == true ? shown?.markerLine : nil
                )
            default: return nil
        }
    }

    /// `spans` by the shown output's hard lines: a folded output's tail follows its head, past the hidden middle.
    private func shownSpans(_ spans: [[OutputEscapes.Span]], at index: Int) -> [[OutputEscapes.Span]] {
        guard let shown = shownToolOutput(at: index), shown.folded, let head = shown.markerLine else { return spans }
        let tail = Swift.min(spans.count, head + shown.hiddenLines)
        return Array(spans.prefix(head)) + spans[tail...]
    }

    /// A tool's output that is JSON or a unified diff, by its content (roadmap 0152, phase 5); nil for any other output.
    private func recognisedCode(at index: Int, output: String) -> FileCode? {
        let shown = shownToolOutput(at: index)
        let restart = shown?.folded == true ? shown?.markerLine : nil
        switch RecognisedOutput.recognise(shown?.text ?? output) {
            case .json: return FileCode(part: .output, language: .json, restart: restart)
            case .diff(let language):
                return FileCode(part: .output, language: language ?? .plain, restart: restart, diff: .unified)
            case nil: return nil
        }
    }

    /// The language of the file at `path` whose text starts as `text` does; nil when it is plain.
    private static func language(of path: String, text: String) -> Language? {
        let language = Language(path: path, firstLine: text.split(separator: "\n", maxSplits: 1).first)
        return language == .plain ? nil : language
    }
}
