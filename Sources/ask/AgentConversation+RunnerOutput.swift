internal import AskTools

/// What a focused job's lane shows.
extension AgentConversation {
    func watchRunnerOutput(_ id: String, update: @escaping @Sendable (String) -> Void) -> Task<Void, Never> {
        let jobs = jobs
        return Task {
            for await _ in jobs.outputChanges(of: id) {
                guard !Task.isCancelled else { return }
                update(jobs.outputTail(of: id, maximumBytes: 64 << 10) ?? "(no output yet)")
            }
        }
    }

    func runnerOutput(_ id: String) async -> String {
        jobs.outputTail(of: id, maximumBytes: 64 << 10) ?? "(no output was recorded for \(id))"
    }
}
