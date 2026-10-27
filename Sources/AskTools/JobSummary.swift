/// A job still running, as the screen lists it: its name and the command it runs.
public struct JobSummary: Sendable, Equatable {
    public let id: String
    public let displayID: String
    public let command: String
    public let startedAt: ContinuousClock.Instant

    public init(id: String, command: String, startedAt: ContinuousClock.Instant, displayID: String? = nil) {
        self.id = id
        self.displayID = displayID ?? id
        self.command = command
        self.startedAt = startedAt
    }
}
