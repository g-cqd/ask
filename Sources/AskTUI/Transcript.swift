/// The conversation as the screen shows it. Independent of the agent: the composition root translates agent
/// events into these calls, so AskTUI depends on TerminalKit only (ADR-0009).
public struct Transcript: Sendable, Equatable {
    /// How a tool call ended, as far as the screen is concerned.
    public enum ToolStatus: Sendable, Equatable {
        case running
        case succeeded
        case failed(String)
    }

    /// One thing in the conversation.
    public enum Item: Sendable, Equatable {
        case user(String)
        case assistant(String)
        case tool(name: String, summary: String, status: ToolStatus)
        case notice(String, isError: Bool)
    }

    public private(set) var items: [Item] = []
    /// Bumped whenever an item changes, so layouts can cache each item's wrapped lines.
    public private(set) var revisions: [Int] = []
    private var nextRevision = 0

    /// An empty transcript.
    public init() {}

    /// Removes the conversation while keeping revisions monotonic. A renderer that skipped the empty frame
    /// must not mistake the next item's revision for the old item's.
    public mutating func removeAll() {
        items.removeAll(keepingCapacity: true)
        revisions.removeAll(keepingCapacity: true)
    }

    public mutating func addUser(_ text: String) { append(.user(text)) }

    /// Appends streamed assistant text, continuing the current assistant item when it is the last one.
    public mutating func addAssistantText(_ text: String) {
        if case .assistant(let existing) = items.last {
            replaceLast(.assistant(existing + text))
        } else {
            append(.assistant(text))
        }
    }

    public mutating func startTool(name: String, summary: String) {
        append(.tool(name: name, summary: summary, status: .running))
    }

    /// Ends the most recent running tool.
    public mutating func finishTool(_ status: ToolStatus) {
        guard
            let index = items.lastIndex(where: {
                if case .tool(_, _, .running) = $0 { return true }
                return false
            }), case .tool(let name, let summary, _) = items[index]
        else { return }
        items[index] = .tool(name: name, summary: summary, status: status)
        revisions[index] = bump()
    }

    public mutating func addNotice(_ text: String, isError: Bool) { append(.notice(text, isError: isError)) }

    private mutating func append(_ item: Item) {
        items.append(item)
        revisions.append(bump())
    }

    private mutating func replaceLast(_ item: Item) {
        items[items.count - 1] = item
        revisions[revisions.count - 1] = bump()
    }

    private mutating func bump() -> Int {
        nextRevision += 1
        return nextRevision
    }
}
