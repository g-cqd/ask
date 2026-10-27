/// A non-consuming bounded view of a process for the screen, separate from unread tool output.
public struct JobSnapshot: Sendable, Equatable {
    public let id: String
    public let displayID: String
    public let output: String
    public let status: JobStatus
    public let startedAt: ContinuousClock.Instant
    public let endedAt: ContinuousClock.Instant?
    public let lines: Int

    public init(
        id: String, output: String, status: JobStatus, startedAt: ContinuousClock.Instant,
        endedAt: ContinuousClock.Instant?, lines: Int, displayID: String? = nil
    ) {
        self.id = id
        self.displayID = displayID ?? id
        self.output = output
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lines = lines
    }
}
