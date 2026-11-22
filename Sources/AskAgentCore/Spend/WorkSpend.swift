public import AskAI

/// What a piece of work cost (roadmap 0239): requests, tokens by kind, tool calls, and time, split into the model's and the tools'.
/// Read from a session's entries and their times, never kept apart from them, except in a done task's record, which keeps what its
/// work cost when it was done. Every count the provider did not report stays nil, and every time an older ask did not record, too.
public struct WorkSpend: Sendable, Equatable {
    /// Responses received.
    public var requests = 0
    /// Their tokens, summed; a kind no response reported stays nil.
    public var usage = TokenUsage()
    /// Tool results recorded.
    public var toolCalls = 0
    /// From the first entry to the last, in milliseconds; nil without two timed entries.
    public var wallMilliseconds: Int?
    /// Waiting for responses: from the entry before each to it.
    public var modelMilliseconds: Int?
    /// Running tools, and waiting for the person to approve them: from the entry before each result to it.
    public var toolMilliseconds: Int?
    /// The models that answered, each once, in the order they first did.
    public var models: [String] = []

    public init() {}

    /// What the work in `entries`, in the order they were recorded, cost.
    public init(of entries: some Sequence<SessionEntry>) {
        var first: Int?
        var previous: Int?
        for entry in entries {
            if case .response = entry.kind, let spent = entry.spent {
                requests += 1
                usage = usage.adding(spent.usage)
                if !models.contains(spent.model) { models.append(spent.model) }
            }
            if case .toolResult = entry.kind { toolCalls += 1 }
            guard let time = entry.recordedAt else { continue }
            if let previous {
                let gap = Swift.max(0, time - previous)
                switch entry.kind {
                    case .response: modelMilliseconds = (modelMilliseconds ?? 0) + gap
                    case .toolResult: toolMilliseconds = (toolMilliseconds ?? 0) + gap
                    default: break
                }
            }
            first = first ?? time
            previous = time
        }
        if let first, let previous, previous > first { wallMilliseconds = previous - first }
    }

    /// Whether nothing was spent: no request and no tool call.
    public var isEmpty: Bool { requests == 0 && toolCalls == 0 }

    /// Both, added: what a task reopened and done again cost over its spells, or a session over its turns.
    public static func + (left: WorkSpend, right: WorkSpend) -> WorkSpend {
        var sum = left
        sum.requests += right.requests
        sum.usage = left.usage.adding(right.usage)
        sum.toolCalls += right.toolCalls
        sum.wallMilliseconds = add(left.wallMilliseconds, right.wallMilliseconds)
        sum.modelMilliseconds = add(left.modelMilliseconds, right.modelMilliseconds)
        sum.toolMilliseconds = add(left.toolMilliseconds, right.toolMilliseconds)
        sum.models += right.models.filter { !left.models.contains($0) }
        return sum
    }

    /// Both added, or the one that is known, or nil when neither is.
    private static func add(_ left: Int?, _ right: Int?) -> Int? {
        switch (left, right) {
            case (nil, nil): nil
            default: (left ?? 0) + (right ?? 0)
        }
    }
}

extension WorkSpend {
    /// The tokens as the status line says the session's: `↑45k ↓3.1k`, every prompt token sent, cached or not, then those received;
    /// a side no response counted is left out, and nil when neither was.
    public var compactTokens: String? {
        let counted = [usage.input, usage.cacheRead, usage.cacheCreation].compactMap(\.self)
        let sent = counted.isEmpty ? nil : "↑" + UsageTotals.short(counted.reduce(0, +))
        let received = usage.output.map { "↓" + UsageTotals.short($0) }
        let both = [sent, received].compactMap(\.self)
        return both.isEmpty ? nil : both.joined(separator: " ")
    }

    /// The entries after `start` on `tree`'s active branch: a turn's, when `start` was the leaf as it began; the whole branch when
    /// `start` is nil or no longer on it.
    public static func since(_ start: EntryID?, in tree: SessionTree) -> WorkSpend {
        let branch = tree.activeBranch()
        let from = start.flatMap { start in branch.lastIndex { $0.id == start }.map { $0 + 1 } } ?? 0
        return WorkSpend(of: branch[from...])
    }
}
