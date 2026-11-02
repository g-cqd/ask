/// What a hook answers when a run would end (roadmap 0192).
public enum RunStopDecision: Sendable, Equatable {
    /// Let it end.
    case stop
    /// Send `message` to the model, as a user entry labelled with the hook's name, and go on.
    case `continue`(String)
}
