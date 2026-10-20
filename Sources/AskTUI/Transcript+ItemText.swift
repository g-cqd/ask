extension Transcript {
    /// The text a selection can take from the item at `index`: what is shown, so a folded block copies as its placeholder line.
    func contentText(at index: Int) -> String {
        items[index].contentText(folded: isFolded(index))
    }
}

extension Transcript.Item {
    /// The text a selection can take from this item.
    func contentText(folded: Bool) -> String {
        switch self {
            case .user(let text), .assistant(let text), .notice(let text, _): return text
            case .thinking(let text):
                let body = Transcript.kept(text)
                let header = Self.thinkingHeader(body: body, folded: folded)
                return body.isEmpty || folded ? header : header + "\n" + body
            case .tool(let name, let summary, let status, let output):
                let header = Self.toolHeader(
                    name: name, summary: summary, status: status, output: output, folded: folded)
                return output.isEmpty || folded ? header : header + "\n" + output
        }
    }

    /// The one line a tool block starts with: its name and summary, how it ended, and when it has output, whether it is folded and
    /// how much it holds. Line feeds are flattened so the header is always hard line 0, the line a click toggles.
    static func toolHeader(
        name: String, summary: String, status: Transcript.ToolStatus, output: String, folded: Bool
    ) -> String {
        let body = "\(name) \(summary)\(toolMark(status).text)".replacing("\n", with: " ")
        guard !output.isEmpty else { return "▸ " + body }
        if !folded { return "▾ " + body }
        let count = TranscriptContent.hardLines(of: output).count
        return "▸ \(body) · \(count) \(count == 1 ? "line" : "lines")"
    }

    /// The one line a thinking block starts with: `▸ thinking · 3 lines` folded, `▾ thinking` open.
    static func thinkingHeader(body: String, folded: Bool) -> String {
        guard !body.isEmpty else { return "▸ thinking" }
        if !folded { return "▾ thinking" }
        let count = TranscriptContent.hardLines(of: body).count
        return "▸ thinking · \(count) \(count == 1 ? "line" : "lines")"
    }

    /// What follows a tool's summary, and how it is styled.
    static func toolMark(_ status: Transcript.ToolStatus) -> (text: String, isFailure: Bool) {
        switch status {
            case .running: (" …", false)
            case .succeeded: (" ✓", false)
            case .failed(let reason): (" ✗ " + reason, true)
        }
    }
}
