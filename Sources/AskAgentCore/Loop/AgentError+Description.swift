extension AgentError: CustomStringConvertible {
    /// A sentence for the person reading it.
    public var description: String {
        switch self {
            case .provider(let reason): reason
            // @dl:accept -- describing an unrelated enum (JobStatus) case by case gives the same shape, not a shared meaning
            case .assembly(let error): "the response broke the protocol: \(error)"
            case .session(let error): "the session could not be recorded: \(error)"
            case .cancelled: "the run was cancelled"
            case .turnLimit(let turns): "stopped after \(turns) requests; raise --max-turns to let it go further"
            case .contextOverflow(let reason):
                "the conversation does not fit the model's context window, even after compacting (\(reason)); "
                    + "declare the model's contextWindow in providers.json, or start the server with a larger context"
        }
    }
}
