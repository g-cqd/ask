extension Transcript {
    /// The text a selection can take from the item at `index`: what is shown, so a folded block copies as its placeholder line.
    func contentText(at index: Int) -> String {
        shownCode(at: index)?.text
            ?? items[index]
            .contentText(
                folded: isFolded(index), toolInput: shownToolInput(at: index)?.text,
                command: commandBlocks.contains(index))
    }
}

extension Transcript.Item {
    /// The text a selection can take from this item.
    func contentText(folded: Bool, toolInput: String? = nil, command: Bool = false) -> String {
        switch self {
            case .user(let text), .assistant(let text), .notice(let text, _), .queued(let text): return text
            case .jobEnded(let label, _, _): return label
            case .thinking(let text):
                let body = Transcript.kept(text)
                let header = Self.thinkingHeader(body: body, folded: folded)
                return folded || !Transcript.saysSomething(body) ? header : body
            case .tool(let name, let summary, _, let output, let input) where command:
                let header = Self.commandHeader(
                    name: name, parameters: summary, command: toolInput ?? input, folded: folded)
                return folded || output.isEmpty ? header : header + "\n" + output
            case .tool(let name, let summary, let status, let output, let input):
                let header = Self.toolHeader(
                    name: name, summary: summary, status: status, output: output, folded: folded)
                guard !folded else { return header }
                let shown = toolInput ?? ShownToolInput(input, isFolded: { _ in true }).text
                return ([header] + (shown.isEmpty ? [] : [shown]) + (output.isEmpty ? [] : [output]))
                    .joined(separator: "\n")
        }
    }

    /// Selectable tool content, without the separately drawn status. Line feeds flatten to hard line zero.
    static func toolHeader(
        name: String, summary: String, status _: Transcript.ToolStatus, output _: String, folded _: Bool
    ) -> String {
        "\(name) · \(summary)".replacing("\n", with: " ")
    }

    /// A command block's header (roadmap 0080): the tool, its limits, then the command. Folded, only the command's first line, with `…`
    /// when more lines follow; open, the whole command, whose lines continue below the header row instead of being shown a second time.
    static func commandHeader(name: String, parameters: String, command: String, folded: Bool) -> String {
        let lead = ([name] + (parameters.isEmpty ? [] : [parameters])).joined(separator: " · ") + " · "
        guard folded else { return lead + command }
        let lines = command.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return lead + (lines.first.map(String.init) ?? "") + (lines.count > 1 ? " …" : "")
    }

    /// The one line a thinking block starts with, folded or open: `Thinking...`, which a click folds and opens.
    static func thinkingHeader(body _: String, folded _: Bool) -> String { "Thinking..." }
}
