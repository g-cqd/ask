internal import AskAgentCore
internal import AskTUI
internal import AskTools

extension AgentConversation {
    /// Says why a run or command ended without finishing.
    func report(_ error: any Error, to update: @Sendable (ConversationUpdate) -> Void) {
        if case AgentError.cancelled = error {
            update(.notice("Aborted. Results already known were kept.", isError: false))
        } else {
            update(.notice("ask: \(error)", isError: true))
        }
    }

    /// Tells `keepAwake` whenever background jobs start running or all stop (roadmap 0090), for as long as the process lives: jobs
    /// outlive turns, and a job still running is ask still working.
    static func follow(_ jobs: JobTable, with keepAwake: KeepAwake) {
        Task {
            for await running in jobs.changes() { keepAwake.jobsRunning(!running.isEmpty) }
        }
    }
}
