extension Transcript {
    /// The text a selection can take from the item at `index`: what is shown, so a folded block copies as its placeholder line.
    func contentText(at index: Int) -> String {
        shownCode(at: index)?.text ?? items[index].contentText(folded: isFolded(index))
    }
}

extension Transcript.Item {
    /// The text a selection can take from this item.
    func contentText(folded: Bool) -> String {
        switch self {
            case .user(let text), .assistant(let text), .notice(let text, _): return text
            case .jobEnded(let label, _, _): return label
            case .thinking(let text):
                let body = Transcript.kept(text)
                let header = Self.thinkingHeader(body: body, folded: folded)
                return body.isEmpty || folded ? header : body
            case .tool(let name, let summary, let status, let output):
                let header = Self.toolHeader(
                    name: name, summary: summary, status: status, output: output, folded: folded)
                return output.isEmpty || folded ? header : header + "\n" + output
        }
    }

    /// Selectable tool content, without the separately drawn status. Line feeds flatten to hard line zero.
    static func toolHeader(
        name: String, summary: String, status _: Transcript.ToolStatus, output _: String, folded _: Bool
    ) -> String {
        "\(name) \(summary)".replacing("\n", with: " ")
    }

    /// The one line a thinking block starts with, folded or open: `Thinking...`, which a click folds and opens.
    static func thinkingHeader(body _: String, folded _: Bool) -> String { "Thinking..." }
}
