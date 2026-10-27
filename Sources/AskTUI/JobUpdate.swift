/// A bounded, non-consuming job snapshot. The composition root maps process outcomes to screen status.
public struct JobUpdate: Sendable, Equatable {
    public let id: String
    public let label: String
    public let output: String
    public let status: Transcript.ToolStatus
    public let startedAt: ContinuousClock.Instant
    public let endedAt: ContinuousClock.Instant?
    public let lines: Int
    public let ending: String

    public init(
        id: String, label: String, output: String, status: Transcript.ToolStatus,
        startedAt: ContinuousClock.Instant, endedAt: ContinuousClock.Instant? = nil,
        lines: Int = 0, ending: String = "ended"
    ) {
        self.id = id
        self.label = label
        self.output = output
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.lines = lines
        self.ending = ending
    }
}
