/// One change to a task list, as it is kept (ADR-0140): the list is these, replayed.
public enum TaskChange: Equatable, Sendable {
    case add(SessionTask)
    case edit(id: Int, title: String?, detail: String?)
    /// `at`, when given, is when it was made done (ADR-0141).
    case state(id: Int, TaskState, at: Int? = nil)
    /// The task put just before `next`, or just after it.
    case place(id: Int, next: Int, after: Bool)
    case link(id: Int, TaskLink, target: Int)
    case unlink(id: Int, TaskLink, target: Int)
    case remove(id: Int)
    /// The tags replaced (ADR-0141).
    case tags(id: Int, [String])
    /// A call's changes, kept as one record so they are kept or lost together (ADR-0141); never nested.
    indirect case batch([TaskChange])

    public static func move(id: Int, before next: Int) -> TaskChange { .place(id: id, next: next, after: false) }
    public static func move(id: Int, after next: Int) -> TaskChange { .place(id: id, next: next, after: true) }
}
