extension Transcript {
    /// The text a selection can take from the item at `index`: what is shown, so a folded block copies as its placeholder line.
    func contentText(at index: Int) -> String {
        shownCode(at: index)?.text
            ?? items[index]
            .contentText(
                folded: isFolded(index),
                running: progress[index].map { $0.ended == nil } ?? false,
                toolInput: shownToolInput(at: index)?.text,
                command: commandBlocks.contains(index),
                output: shownToolOutput(at: index)?.text
            )
    }
}

extension Transcript.Item {
    /// The text a selection can take from this item.
    func contentText(
        folded: Bool,
        running: Bool = false,
        toolInput: String? = nil,
        command: Bool = false,
        output shown: String? = nil
    ) -> String {
        switch self {
            case .user(let text), .assistant(let text), .notice(let text, _), .queued(let text): return text
            case .jobEnded(let label, _, _): return label
            case .trimmed: return ""
            case .thinking(let text):
                let body = Transcript.kept(text)
                let header = Self.thinkingHeader(running: running)
                return folded || !Transcript.saysSomething(body) ? header : body
            case .tool(let name, let summary, _, let whole, let input) where command:
                let output = shown ?? whole
                let header = Self.commandHeader(
                    name: name,
                    parameters: summary,
                    command: toolInput ?? input,
                    folded: folded
                )
                return folded || output.isEmpty ? header : header + "\n" + output
            case .tool(let name, let summary, let status, let whole, let input):
                let output = shown ?? whole
                let header = Self.toolHeader(
                    name: name,
                    summary: summary,
                    status: status,
                    output: output,
                    folded: folded
                )
                guard !folded else { return header }
                let shown = toolInput ?? ShownToolInput(input, isFolded: { _ in true }).text
                return ([header] + (shown.isEmpty ? [] : [shown]) + (output.isEmpty ? [] : [output]))
                    .joined(separator: "\n")
        }
    }

    /// Selectable tool content, without the separately drawn status. Line feeds flatten to hard line zero.
    static func toolHeader(
        name: String,
        summary: String,
        status _: Transcript.ToolStatus,
        output _: String,
        folded _: Bool
    ) -> String {
        // Nothing after the name when there is nothing to say (note n70).
        (summary.isEmpty ? name : "\(name) · \(summary)").replacing("\n", with: " ")
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
    /// A thinking block's header: what it is doing while it streams, what it did once it has ended (note n37).
    static func thinkingHeader(running: Bool) -> String { running ? "Thinking..." : "Thought." }
}

extension Transcript.Item {
    /// The same tool with `output` in place of its own: what the body draws once the middle of a long output is folded away.
    func showing(_ output: String) -> Self {
        guard case .tool(let name, let summary, let status, _, let input) = self else { return self }
        return .tool(name: name, summary: summary, status: status, output: output, fullInput: input)
    }
}
