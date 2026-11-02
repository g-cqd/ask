public import AskAI

/// Why a run ended without finishing.
public enum AgentError: Error, Sendable, Equatable {
    /// The provider failed; its description, for the user.
    case provider(String)
    /// The response stream broke the protocol.
    case assembly(ResponseAssemblyError)
    /// A change could not be recorded. Nothing after it ran.
    case session(SessionFileError)
    /// The run was aborted. Results already known are recorded; calls not yet run are left unanswered.
    case cancelled
    case turnLimit(Int)
    /// The request was longer than the model's context window even after compacting; the provider's words.
    case contextOverflow(String)
    /// A hook kept the run's first message out (roadmap 0192); nothing was recorded or sent.
    case promptBlocked(String)
}
