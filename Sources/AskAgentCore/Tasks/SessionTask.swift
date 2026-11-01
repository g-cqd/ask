/// One task of a session's list (ADR-0140).
public struct SessionTask: Codable, Sendable, Equatable {
    /// `t1`, `t2`, … in the order tasks are made; never reused.
    public let id: Int
    /// One line.
    public var title: String
    /// Any length, shown on demand.
    public var detail: String
    public var state: TaskState
    public var blockedBy: [Int]
    public var related: [Int]

    /// How the task is named: `t5`.
    public var name: String { "t\(id)" }
}
