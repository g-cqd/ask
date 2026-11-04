public import AskAI

/// What a hook answers before a request is sent to the model (roadmap 0192, ADR-0143).
public enum RequestBeforeDecision: Sendable, Equatable {
    /// Send the request as it is.
    case allow
    /// Send this request instead, for this request only.
    case rewrite(ModelRequest)
}
