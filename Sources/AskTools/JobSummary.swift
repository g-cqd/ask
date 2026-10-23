/// A job still running, as the screen lists it: its name and the command it runs.
public struct JobSummary: Sendable, Equatable {
    public let id: String
    public let command: String

    public init(id: String, command: String) {
        self.id = id
        self.command = command
    }
}
