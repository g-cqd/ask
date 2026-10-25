internal import AskTools

/// What a focused job's lane shows.
extension AgentConversation {
    func runnerOutput(_ id: String) async -> String {
        jobs.outputTail(of: id, maximumBytes: 64 << 10) ?? "(no output was recorded for \(id))"
    }
}
