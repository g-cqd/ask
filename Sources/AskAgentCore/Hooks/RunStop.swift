public import AskAI

/// What a hook is shown when a run would end (roadmap 0192): the reply that ends it, and how many times hooks already continued it.
public struct RunStop: Sendable, Equatable {
    /// The reply without tool calls that would end the run.
    public let response: AssembledResponse
    /// How many times hooks have continued this run, so a hook can stop itself before the limit does.
    public let continued: Int
    /// Whether the run made a call that changes things (a command, a write, an edit, input to a job) since the last stop, or since it
    /// began.
    public let changed: Bool

    public init(response: AssembledResponse, continued: Int, changed: Bool = false) {
        self.response = response
        self.continued = continued
        self.changed = changed
    }
}
