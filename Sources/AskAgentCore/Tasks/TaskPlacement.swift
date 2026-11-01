/// Where `move` puts a task: before another, or last.
public enum TaskPlacement: Sendable, Equatable {
    case before(ListRef)
    case end
}
