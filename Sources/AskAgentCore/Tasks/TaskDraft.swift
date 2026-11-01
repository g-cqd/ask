/// A task to add, as asked.
public struct TaskDraft: Sendable, Equatable {
    public var title: String
    public var detail: String
    public var state: TaskState
    public var tags: [String]
    public var blockedBy: [ListRef]
    public var related: [ListRef]

    public init(
        title: String,
        detail: String = "",
        state: TaskState = .open,
        // @dl:accept -- a memberwise initialiser or a field table reads like any other of its kind; the fields are the data
        tags: [String] = [],
        blockedBy: [ListRef] = [],
        related: [ListRef] = []
    ) {
        self.title = title
        self.detail = detail
        self.state = state
        self.tags = tags
        self.blockedBy = blockedBy
        self.related = related
    }
}
