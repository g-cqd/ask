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
        case tool(name: String, summary: String, status: ToolStatus, output: String, fullInput: String = "")
        /// What the model reasoned before answering, kept so it can be opened (ADR-0046: `ui.thinking`).
        case thinking(String)
        case notice(String, isError: Bool)
        /// A message sent while a turn runs, waiting for the model to take it (steering or a follow-up): drawn dim, with a spinner and no
        /// background, and replaced by the user's message once it is accepted (roadmap 0129).
        case queued(String)
        /// A completed background job, with status metadata drawn at the right edge.
        case jobEnded(label: String, status: ToolStatus, lines: Int)
    }

    public internal(set) var items: [Item] = []
    /// Bumped whenever an item changes, so layouts can cache each item's wrapped lines.
    public internal(set) var revisions: [Int] = []
    private var nextRevision = 0
    var progress: [Int: BlockProgress] = [:]
    var toolBlocks: [String: Int] = [:]
    /// The tool blocks whose input is a command, which heads the block (roadmap 0080).
    var commandBlocks: Set<Int> = []
    var jobBlocks: [String: Int] = [:]
    var completedJobs: Set<String> = []
    /// Which tool blocks the user opened or closed, over the default for the kind (TerminalKit roadmap 0018).
    var folds = FoldStore<Int>()
    /// Whether a tool block with output starts folded, unless the user chose (ADR-0046: `ui.tools`).
    public private(set) var toolsFoldedByDefault = true
    /// Whether a thinking block starts folded, unless the user chose.
    public private(set) var thinkingFoldedByDefault = true
    /// Which long code blocks the user opened or closed, over ``codeFoldedByDefault``.
    var codeFolds = FoldStore<CodeBlockID>()
    /// Whether a long code block starts folded, unless the user chose (`ui.code`).
    public internal(set) var codeFoldedByDefault = true
    /// A code block with more lines than this can fold (ADR-0046: `ui.codeFoldLines`, never more than half the screen).
    public internal(set) var codeFoldLines = 20
    /// Whether assistant messages are drawn as Markdown (roadmap 0065: `ui.markdown`) rather than as the text the model wrote.
    public internal(set) var markdown = false
    /// Which spinner style is used for progress indicators in live blocks.
    public var spinnerStyle: SpinnerStyle = .line
    /// Whether a command's limits are written in the locale's units or as a clock (`ui.localizedDurations`).
    public var localizedDurations = true
    /// The home folder that a tool's path is written without (roadmap 0128).
    public var home: String?
    /// The most lines of one tool's output kept; the rest is said, not stored, so one huge output cannot slow every frame.
    static let outputLineLimit = 400

    /// An empty transcript.
    public init() {}

    /// An empty transcript whose revisions cannot equal another transcript's, so a layout cache never mistakes one for the other.
    init(revisionBase: Int) { nextRevision = revisionBase }

    /// Removes the conversation while keeping revisions monotonic. A renderer that skipped the empty frame
    /// must not mistake the next item's revision for the old item's.
    public mutating func removeAll() {
        items.removeAll(keepingCapacity: true)
        revisions.removeAll(keepingCapacity: true)
        progress.removeAll(keepingCapacity: true)
        toolBlocks.removeAll(keepingCapacity: true)
        commandBlocks.removeAll(keepingCapacity: true)
        jobBlocks.removeAll(keepingCapacity: true)
        completedJobs.removeAll(keepingCapacity: true)
        folds.clearChoices()
        codeFolds.clearChoices()
    }

    public mutating func addUser(_ text: String) { append(.user(text)) }

    /// Appends streamed reasoning, continuing the current thinking block when it is the last item.
    public mutating func addThinkingText(_ text: String) { stream(text, as: Item.thinking) }

    /// Appends streamed assistant text, continuing the current assistant item when it is the last one.
    public mutating func addAssistantText(_ text: String) { stream(text, as: Item.assistant) }

    /// Continues the last item when it is of the kind `make` makes, or starts one.
    private mutating func stream(_ text: String, as make: (String) -> Item) {
        switch (items.last, make("")) {
            case (.thinking(let existing)?, .thinking), (.assistant(let existing)?, .assistant):
                replaceLast(make(existing + text))
            default: append(make(text))
        }
    }

    public mutating func startTool(
        name: String, summary: String, at now: ContinuousClock.Instant = .now, id: String? = nil,
        fullInput: String = "",
        command: ToolCommand? = nil
    ) {
        let summary =
            command.map { $0.parameters(localized: localizedDurations) } ?? HomePath.abbreviate(summary, home: home)
        append(.tool(name: name, summary: summary, status: .running, output: "", fullInput: fullInput))
        progress[items.count - 1] = BlockProgress(at: now, spinner: spinnerStyle)
        if command != nil { commandBlocks.insert(items.count - 1) }
        if let id { toolBlocks[id] = items.count - 1 }
    }

    /// Ends the most recent running tool, keeping what it returned.
    public mutating func finishTool(
        _ status: ToolStatus, output: String = "", at now: ContinuousClock.Instant = .now,
        id: String? = nil, backgroundJob: String? = nil
    ) {
        guard
            let index = id.flatMap({ toolBlocks[$0] }) ?? (id == nil ? latestForegroundTool : nil),
            case .tool(let name, let summary, _, _, let input) = items[index]
        else { return }
        finishProgress(at: index, now: now)
        items[index] = .tool(name: name, summary: summary, status: status, output: Self.kept(output), fullInput: input)
        revisions[index] = bump()
        if let backgroundJob { jobBlocks[backgroundJob] = index }
    }

    /// Whether reasoning says anything: a block of white space, or nothing at all, does not (roadmap 0081).
    static func saysSomething(_ text: String) -> Bool { text.contains { !$0.isWhitespace } }

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
            case .tool(_, _, _, let output, let input): return !output.isEmpty || !input.isEmpty
            case .thinking(let text): return Self.saysSomething(text)
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

    mutating func append(_ item: Item) {
        finishThinking()
        items.append(item)
        if case .thinking = item { progress[items.count - 1] = BlockProgress(at: .now, spinner: spinnerStyle) }
        revisions.append(bump())
    }

    private mutating func replaceLast(_ item: Item) {
        items[items.count - 1] = item
        revisions[revisions.count - 1] = bump()
    }

    mutating func bump() -> Int {
        nextRevision += 1
        return nextRevision
    }
}
