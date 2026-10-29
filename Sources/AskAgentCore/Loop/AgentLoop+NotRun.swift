extension AgentLoop {
    /// The result recorded for a call the turn never started, because it was stopped first.
    public static let notRunResult = "Not run: the turn was stopped before this tool started."

    /// Records every call of `calls` as not run, so the session answers each call it holds and the next request needs no repair. Without
    /// this, every request after a stop rebuilt the same answer and said so again.
    func recordNotRun(_ calls: ArraySlice<ToolInvocation>, in session: SessionRecorder) throws(AgentError) {
        for call in calls {
            try record(.toolResult(callID: call.id, content: Self.notRunResult, isError: true), in: session)
        }
    }
}
