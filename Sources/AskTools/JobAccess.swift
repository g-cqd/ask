internal import AskAgentCore

/// What every job tool holds: the shared table, and the clock its time limits run on.
struct JobAccess: Sendable {
    let jobs: JobTable
    let clock: any Clock<Duration>

    /// The job named `id`.
    /// - Throws: a ``ToolFailure`` naming it when there is none, saying so when it finished and was let go (`jobs.keepFinished`).
    func job(_ id: String) throws(ToolFailure) -> Job {
        guard let job = jobs.job(id) else {
            guard jobs.wasLetGo(id) else { throw ToolFailure("No job named \(id).") }
            throw ToolFailure(
                "\(id) finished and was let go, with its output: jobs.keepFinished keeps only the most recent finished jobs."
            )
        }
        return job
    }
}
