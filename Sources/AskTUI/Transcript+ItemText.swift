extension Transcript.Item {
    /// The text a selection can take from this item.
    var contentText: String {
        switch self {
            case .user(let text), .assistant(let text), .notice(let text, _): text
            case .tool(let name, let summary, let status): "▸ \(name) \(summary)\(Self.toolMark(status).text)"
        }
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
