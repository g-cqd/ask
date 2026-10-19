public import AskAI

/// What a hook decides about a tool call before it runs.
public enum ToolCallDecision: Sendable, Equatable {
    /// Let it run as it is.
    case allow
    /// Do not run it; the model receives an error result giving `reason`, so it can choose another course.
    case block(reason: String)
    /// Run it with this input instead.
    case rewrite(JSONObject)
}
