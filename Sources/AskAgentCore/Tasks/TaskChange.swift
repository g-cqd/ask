/// One change to a task list, as it is kept (ADR-0140): the list is these, replayed.
public enum TaskChange: Equatable, Sendable {
    case add(SessionTask)
    case edit(id: Int, title: String?, detail: String?)
    case state(id: Int, TaskState)
    /// The task put just before `next`, or just after it.
    case place(id: Int, next: Int, after: Bool)
    case link(id: Int, TaskLink, target: Int)
    case unlink(id: Int, TaskLink, target: Int)
    case remove(id: Int)

    public static func move(id: Int, before next: Int) -> TaskChange { .place(id: id, next: next, after: false) }
    public static func move(id: Int, after next: Int) -> TaskChange { .place(id: id, next: next, after: true) }
}
