public import Foundation

/// A `read` of the task list (ADR-0141): which tasks, how much of each, how many at most.
public struct TaskQuery: Sendable, Equatable {
    public enum View: String, Sendable, CaseIterable {
        // @dl:accept -- the tasks and the ideas are two lists of one store (ADR-0141): their reads, inputs, tools and records share a shape over different fields
        case open, done, all, summary
    }

    public var view: View
    /// Those tasks, whatever their state, each in full.
    public var ids: [ListRef]
    /// Words that must all appear in a task's title, detail or tags; see ADR-0141's "Search".
    public var text: String?
    public var limit: Int

    public init(
        view: View = .open,
        ids: [ListRef] = [],
        text: String? = nil,
        limit: Int = ListLimits.defaultReadLimit
    ) {
        self.view = view
        self.ids = ids
        self.text = text
        self.limit = limit
    }

    /// What the read shows of `list`.
    public func answer(_ list: TaskList, in zone: TimeZone = .current) throws(ListPlanError) -> String {
        try check()
        guard !list.tasks.isEmpty else { return "No tasks yet." }
        let chosen = try select(list)
        if view == .summary { return Self.summary(chosen, of: list) }
        guard !chosen.isEmpty else { return isPlain && view == .open ? "Every task is done." : "No task matches." }
        let shown = chosen.prefix(limit)
        let full = !ids.isEmpty
        var lines = shown.map { full ? (list.showing($0.id, in: zone) ?? "") : list.line($0) }
        if chosen.count > shown.count {
            lines.append("(\(chosen.count - shown.count) more; raise limit, or narrow the read.)")
        }
        let done = list.tasks.count { $0.state == .done }
        if isPlain, view == .open, done > 0 { lines.append("(\(done) done, not shown)") }
        return lines.joined(separator: full ? "\n\n" : "\n")
    }

    private var isPlain: Bool { ids.isEmpty && text == nil }

    private func check() throws(ListPlanError) {
        guard (1 ... ListLimits.readLimit).contains(limit) else {
            throw Self.refusal("limit is 1 to \(ListLimits.readLimit).")
        }
        if let text, text.count > ListLimits.textLength {
            throw Self.refusal("text has at most \(ListLimits.textLength) characters.")
        }
    }

    private func select(_ list: TaskList) throws(ListPlanError) -> [SessionTask] {
        var chosen: [SessionTask]
        if ids.isEmpty {
            chosen = list.tasks.filter { task in
                switch view {
                    case .open: task.state != .done
                    case .done: task.state == .done
                    case .all, .summary: true
                }
            }
        } else {
            chosen = try Self.named(ids, in: list)
        }
        if let text {
            chosen = ListSearch.rank(chosen, words: text) { [$0.title, $0.tags.joined(separator: " "), $0.detail] }
        }
        return chosen
    }

    private static func named(_ refs: [ListRef], in list: TaskList) throws(ListPlanError) -> [SessionTask] {
        let ids = try ListRef.expand(refs, adds: nil) { refusal($0) }
        if let missing = ids.first(where: { list.task($0) == nil }) { throw refusal("there is no task t\(missing).") }
        let wanted = Set(ids)
        return list.tasks.filter { wanted.contains($0.id) }
    }

    private static func summary(_ chosen: [SessionTask], of list: TaskList) -> String {
        let counts = TaskState.allCases.map { state in "\(chosen.count { $0.state == state }) \(TaskReport.word(state))"
        }
        let blocked = chosen.count { $0.state != .done && list.isBlocked($0.id) }
        var tags: [String: Int] = [:]
        for task in chosen { for tag in task.tags { tags[tag, default: 0] += 1 } }
        var line = "\(chosen.count) tasks: " + counts.joined(separator: ", ")
        if blocked > 0 { line += " · \(blocked) blocked" }
        if !tags.isEmpty {
            line +=
                " · tags: " + tags.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        }
        return line
    }

    static func refusal(_ reason: String) -> ListPlanError {
        ListPlanError(index: 0, operation: "read", reason: reason)
    }
}
