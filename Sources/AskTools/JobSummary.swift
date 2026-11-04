/// A job still running, as the screen lists it: its name and the command it runs.
public struct JobSummary: Sendable, Equatable {
    public let id: String
    public let displayID: String
    public let command: String
    public let startedAt: ContinuousClock.Instant
    /// The thread it was started for (``JobOwner``), nil for main's.
    public let owner: String?

    public init(
        id: String,
        command: String,
        startedAt: ContinuousClock.Instant,
        displayID: String? = nil,
        owner: String? = nil
    ) {
        self.id = id
        self.displayID = displayID ?? id
        self.command = command
        self.startedAt = startedAt
        self.owner = owner
    }
}
