public import Foundation

/// A task list as the model and the person read it (ADR-0140): one line a task, its description on demand.
extension TaskList {
    /// `t2 [open, blocked by t1] Ship it · related t3`.
    public func line(_ task: SessionTask) -> String {
        var state = task.state == .inProgress ? "in progress" : task.state.rawValue
        let waiting = task.blockedBy.filter { self.task($0)?.state != .done }
        if !waiting.isEmpty { state += ", blocked by " + waiting.map { "t\($0)" }.joined(separator: " ") }
        let tags = task.tags.map { " #" + $0 }.joined()
        let related = task.related.isEmpty ? "" : " · related " + task.related.map { "t\($0)" }.joined(separator: " ")
        return "\(task.name) [\(state)] \(task.title)\(tags)\(related)"
    }

    /// Every task not done, or every task with `all`; and how many done ones were left out.
    public func listing(all: Bool) -> String {
        guard !tasks.isEmpty else { return "No tasks yet." }
        let shown = all ? tasks : tasks.filter { $0.state != .done }
        let hidden = tasks.count - shown.count
        var lines = shown.map(line)
        if lines.isEmpty { lines.append("Every task is done.") }
        if hidden > 0 { lines.append("(\(hidden) done, not shown)") }
        return lines.joined(separator: "\n")
    }

    /// A task's line, when it was made and done, then its description and links in full.
    public func showing(_ id: Int, in zone: TimeZone = .current) -> String? {
        guard let task = task(id) else { return nil }
        var lines = [line(task)]
        let times = [
            task.made.map { "made " + ListTime.stamp($0, in: zone) },
            task.closed.map { "done " + ListTime.stamp($0, in: zone) }
        ]
        if !times.compactMap({ $0 }).isEmpty { lines.append(times.compactMap { $0 }.joined(separator: " · ")) }
        if !task.detail.isEmpty { lines += ["", task.detail] }
        if !task.blockedBy.isEmpty {
            lines.append("blocked by: " + task.blockedBy.compactMap { self.task($0).map(line) }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}
