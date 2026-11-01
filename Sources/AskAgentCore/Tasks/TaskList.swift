/// A session's tasks (ADR-0140): in the order the person or the model put them, each change checked before it is made, so the list is
/// always sound: every link names a task that is there, and nothing waits on itself.
// @dl:accept -- the tasks and the ideas are two lists of one store: their declarations, add guards and id lookups share a shape over different fields
public struct TaskList: ChangeList {
    public static let suffix = "tasks"
    public static let workspaceName = "tasks.ask"

    public private(set) var tasks: [SessionTask] = []
    /// The id the next task takes: one more than the largest ever made, so a removed task's id is never given again.
    public private(set) var nextID = 1

    public init() {}

    public func task(_ id: Int) -> SessionTask? { tasks.first { $0.id == id } }

    /// Whether a task it waits on is not done.
    public func isBlocked(_ id: Int) -> Bool {
        task(id)?.blockedBy.contains { task($0)?.state != .done } ?? false
    }

    /// The change that adds a task with the next id.
    public func adding(title: String, detail: String = "", blockedBy: [Int] = [], related: [Int] = []) -> TaskChange {
        .add(
            SessionTask(
                id: nextID,
                title: title,
                detail: detail,
                state: .open,
                blockedBy: blockedBy,
                related: related
            )
        )
    }

    /// Makes `change`, or refuses it and leaves the list as it was.
    public mutating func apply(_ change: TaskChange) throws(TaskListError) {
        var next = self
        try next.make(change)
        self = next
    }

    // @dl:accept -- the tasks and the ideas are two lists of one store: their declarations, add guards and id lookups share a shape over different fields
    private mutating func make(_ change: TaskChange) throws(TaskListError) {
        switch change {
            case .add(let task):
                guard task.id >= nextID else { throw .taken(task.id) }
                guard !task.title.isBlank else { throw .emptyTitle }
                for target in task.blockedBy + task.related where self.task(target) == nil {
                    throw .unknownTask(target)
                }
                tasks.append(task)
                nextID = Swift.max(nextID, task.id + 1)
            case .edit(let id, let title, let detail):
                let index = try place(id)
                if let title {
                    guard !title.isBlank else { throw .emptyTitle }
                    tasks[index].title = title
                }
                if let detail { tasks[index].detail = detail }
            case .state(let id, let state): tasks[try place(id)].state = state
            case .place(let id, let next, let after): try move(id, to: try place(next), after: after)
            case .link(let id, let link, let target): try self.link(id, link, target)
            case .unlink(let id, let link, let target):
                let index = try place(id)
                if link == .blockedBy { tasks[index].blockedBy.removeAll { $0 == target } }
                if link == .related { tasks[index].related.removeAll { $0 == target } }
            case .remove(let id):
                tasks.remove(at: try place(id))
                for index in tasks.indices {
                    tasks[index].blockedBy.removeAll { $0 == id }
                    tasks[index].related.removeAll { $0 == id }
                }
        }
    }

    private mutating func link(_ id: Int, _ link: TaskLink, _ target: Int) throws(TaskListError) {
        let index = try place(id)
        _ = try place(target)
        switch link {
            case .blockedBy:
                guard id != target, !waits(target, on: id) else { throw .cycle }
                if !tasks[index].blockedBy.contains(target) { tasks[index].blockedBy.append(target) }
            case .related:
                if id != target, !tasks[index].related.contains(target) { tasks[index].related.append(target) }
        }
    }

    /// Whether `id` waits on `other`, directly or through others.
    private func waits(_ id: Int, on other: Int) -> Bool {
        var seen: Set<Int> = []
        var pending = [id]
        while let next = pending.popLast() {
            guard seen.insert(next).inserted, let task = task(next) else { continue }
            if task.blockedBy.contains(other) { return true }
            pending += task.blockedBy
        }
        return false
    }

    private mutating func move(_ id: Int, to target: Int, after: Bool) throws(TaskListError) {
        let from = try place(id)
        let moved = tasks.remove(at: from)
        let anchor = target > from ? target - 1 : target
        // @dl:accept -- the tasks and the ideas are two lists of one store: their declarations, add guards and id lookups share a shape over different fields
        tasks.insert(moved, at: after ? anchor + 1 : anchor)
    }

    private func place(_ id: Int) throws(TaskListError) -> Int {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw .unknownTask(id) }
        return index
    }
}
