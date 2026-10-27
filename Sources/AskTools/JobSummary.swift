/// A job still running, as the screen lists it: its name and the command it runs.
public struct JobSummary: Sendable, Equatable {
    public let id: String
    public let command: String
    public let startedAt: ContinuousClock.Instant

    public init(id: String, command: String, startedAt: ContinuousClock.Instant) {
        self.id = id
        self.command = command
        self.startedAt = startedAt
    }
}
