/// The limit that kept hooks from continuing a run (roadmap 0192).
public enum HookContinueLimit: Sendable, Equatable {
    /// Hooks continued the run this many times, the setting's most.
    case continues(Int)
    /// The run reached its turn limit, this many requests.
    case turns(Int)
}
