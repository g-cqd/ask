/// Where a task stands (ADR-0140). "Blocked" is not one: it is shown while a task it waits on is not done.
public enum TaskState: String, Codable, Sendable, CaseIterable {
    case open
    case inProgress
    case done
}
