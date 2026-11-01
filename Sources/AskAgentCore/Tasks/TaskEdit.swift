/// One change a call to the `tasks` tool asks for (ADR-0141), before it is planned: ids as written, values as sent.
public enum TaskEdit: Sendable, Equatable {
    case add(TaskDraft)
    /// One task; at least one of the three.
    case edit(ListRef, title: String?, detail: String?, tags: [String]?)
    case state([ListRef], TaskState)
    case move(ListRef, TaskPlacement)
    /// At least one of the two lists.
    case link([ListRef], blockedBy: [ListRef], related: [ListRef])
    case unlink([ListRef], blockedBy: [ListRef], related: [ListRef])
    case remove([ListRef])

    /// As the call names it, for a refusal to say which change it was.
    public var operation: String {
        switch self {
            case .add: "add"
            case .edit: "edit"
            case .state: "state"
            case .move: "move"
            case .link: "link"
            case .unlink: "unlink"
            case .remove: "remove"
        }
    }
}
