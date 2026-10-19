internal import AskAgentCore

/// What every job tool holds: the shared table, and the clock its time limits run on.
struct JobAccess: Sendable {
    let jobs: JobTable
    let clock: any Clock<Duration>

    /// The job named `id`.
    /// - Throws: a ``ToolFailure`` naming it when there is none.
    func job(_ id: String) throws(ToolFailure) -> Job {
        guard let job = jobs.job(id) else { throw ToolFailure("No job named \(id).") }
        return job
    }
}
