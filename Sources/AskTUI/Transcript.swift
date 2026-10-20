internal import TerminalKitText

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
        /// A tool call. `output` is what it returned, shown when the block is unfolded.
        case tool(name: String, summary: String, status: ToolStatus, output: String)
        /// What the model reasoned before answering, kept so it can be opened (ADR-0046: `ui.thinking`).
        case thinking(String)
        case notice(String, isError: Bool)
    }

    public private(set) var items: [Item] = []
    /// Bumped whenever an item changes, so layouts can cache each item's wrapped lines.
    public private(set) var revisions: [Int] = []
    private var nextRevision = 0
    /// Which tool blocks the user opened or closed, over the default for the kind (TerminalKit roadmap 0018).
    private(set) var folds = FoldStore<Int>()
    /// Whether a tool block with output starts folded, unless the user chose (ADR-0046: `ui.tools`).
    public private(set) var toolsFoldedByDefault = true
    /// Whether a thinking block starts folded, unless the user chose.
    public private(set) var thinkingFoldedByDefault = true
    /// The most lines of one tool's output kept; the rest is said, not stored, so one huge output cannot slow every frame.
    static let outputLineLimit = 400

    /// An empty transcript.
    public init() {}

    /// Removes the conversation while keeping revisions monotonic. A renderer that skipped the empty frame
    /// must not mistake the next item's revision for the old item's.
    public mutating func removeAll() {
        items.removeAll(keepingCapacity: true)
        revisions.removeAll(keepingCapacity: true)
        folds.clearChoices()
    }

    public mutating func addUser(_ text: String) { append(.user(text)) }

    /// Appends streamed reasoning, continuing the current thinking block when it is the last item.
    public mutating func addThinkingText(_ text: String) {
        if case .thinking(let existing) = items.last {
            replaceLast(.thinking(existing + text))
        } else {
            append(.thinking(text))
        }
    }

    /// Appends streamed assistant text, continuing the current assistant item when it is the last one.
    public mutating func addAssistantText(_ text: String) {
        if case .assistant(let existing) = items.last {
            replaceLast(.assistant(existing + text))
        } else {
            append(.assistant(text))
        }
    }

    public mutating func startTool(name: String, summary: String) {
        append(.tool(name: name, summary: summary, status: .running, output: ""))
    }

    /// Ends the most recent running tool, keeping what it returned.
    public mutating func finishTool(_ status: ToolStatus, output: String = "") {
        guard
            let index = items.lastIndex(where: {
                if case .tool(_, _, .running, _) = $0 { return true }
                return false
            }), case .tool(let name, let summary, _, _) = items[index]
        else { return }
        items[index] = .tool(name: name, summary: summary, status: status, output: Self.kept(output))
        revisions[index] = bump()
    }

    /// The output without its trailing line feeds, and at most ``outputLineLimit`` lines, with the cut said.
    static func kept(_ output: String) -> String {
        var text = Substring(output)
        while let last = text.last, last == "\n" || last == "\r\n" || last == "\r" { text = text.dropLast() }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > outputLineLimit else { return String(text) }
        let cut = lines.count - outputLineLimit
        return lines.prefix(outputLineLimit).joined(separator: "\n") + "\n… \(cut) more lines not shown"
    }

    // MARK: - Folding

    /// Whether the item at `index` can fold: a tool that returned something, or reasoning that says something.
    public func isFoldable(_ index: Int) -> Bool {
        guard items.indices.contains(index) else { return false }
        switch items[index] {
            case .tool(_, _, _, let output): return !output.isEmpty
            case .thinking(let text): return !Self.kept(text).isEmpty
            default: return false
        }
    }

    /// Whether blocks of the item's kind start folded: tools and thinking are set apart.
    private func foldsByDefault(_ index: Int) -> Bool {
        if case .thinking = items[index] { return thinkingFoldedByDefault }
        return toolsFoldedByDefault
    }

    /// Whether the item is folded to its placeholder. Only a foldable item ever is.
    public func isFolded(_ index: Int) -> Bool {
        isFoldable(index) && folds.isFolded(index, default: foldsByDefault(index))
    }

    /// Flips one block and says which way it went, or nil if it cannot fold.
    @discardableResult
    public mutating func toggleFold(_ index: Int) -> Bool? {
        guard isFoldable(index) else { return nil }
        let folded = folds.toggle(index, default: foldsByDefault(index))
        revisions[index] = bump()
        return folded
    }

    /// Sets what tool blocks do until the user chooses, and forgets the choices made for tool blocks so it reaches every one.
    public mutating func setToolsFoldedByDefault(_ folded: Bool) {
        toolsFoldedByDefault = folded
        forgetChoices { if case .thinking = $0 { false } else { true } }
    }

    /// Sets what thinking blocks do until the user chooses, and forgets the choices made for them.
    public mutating func setThinkingFoldedByDefault(_ folded: Bool) {
        thinkingFoldedByDefault = folded
        forgetChoices { if case .thinking = $0 { true } else { false } }
    }

    /// Forgets the choices for the items `matches` accepts, and has them laid out again.
    private mutating func forgetChoices(where matches: (Item) -> Bool) {
        for index in items.indices where matches(items[index]) {
            folds.clearChoice(for: index)
            revisions[index] = bump()
        }
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
