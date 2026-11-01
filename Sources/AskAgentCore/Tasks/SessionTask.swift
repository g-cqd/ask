/// One task of a session's list (ADR-0140, ADR-0141).
public struct SessionTask: Sendable, Equatable {
    /// `t1`, `t2`, … in the order tasks are made; never reused.
    public let id: Int
    /// One line, unique in its list (checked when a change is planned).
    public var title: String
    /// Shown on demand.
    public var detail: String
    public var state: TaskState
    public var blockedBy: [Int]
    public var related: [Int]
    /// `[a-z0-9-]{1,24}`, at most 8, sorted.
    public var tags: [String]
    /// When it was made and last done, in seconds since 1970; nil in records from before ADR-0141.
    public var made: Int?
    public var closed: Int?

    public init(
        id: Int,
        title: String,
        detail: String,
        state: TaskState,
        blockedBy: [Int],
        related: [Int],
        tags: [String] = [],
        // @dl:accept -- a memberwise initialiser or a field table reads like any other of its kind; the fields are the data
        made: Int? = nil,
        closed: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
        self.blockedBy = blockedBy
        self.related = related
        self.tags = tags
        self.made = made
        self.closed = closed
    }

    /// How the task is named: `t5`.
    public var name: String { "t\(id)" }
}
