/// How many finished jobs a ``JobTable`` keeps (`jobs.keepFinished`, t232; the owner, 2026-11-06: all of them by default), and the
/// names of those it let go, so a job tool asked about one says so instead of not knowing it.
struct JobRetention: Sendable {
    /// The most finished jobs kept; nil for all of them.
    var limit: Int?
    /// The ids and short ids of the jobs let go.
    var letGo: Set<String> = []
}
