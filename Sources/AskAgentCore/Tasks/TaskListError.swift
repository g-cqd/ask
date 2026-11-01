/// Why a change to a task list was refused; the list is left as it was.
public enum TaskListError: Error, Equatable, Sendable {
    case unknownTask(Int)
    /// A new task with an id given before; two processes adding at once without the lock would make one.
    case taken(Int)
    case emptyTitle
    /// The task would wait on itself, through any number of others.
    case cycle
    /// A batch inside a batch: never written, refused when read.
    case nested
}
