internal import Synchronization

/// The context repairs a loop has already reported. The repairs are rebuilt from the session for every request, so a session damaged before
/// this run (a call left unanswered by an older ask, or by a crash) needs the same repair each time; it is said once. Shared by reference, as
/// ``LearnedWindow`` is, so an interactive conversation that reuses one loop keeps it.
final class ReportedRepairs: Sendable {
    private let seen = Mutex<Set<RequestContext.Repair>>([])

    /// The repairs of `repairs` not reported before, now marked as reported.
    func unreported(_ repairs: [RequestContext.Repair]) -> [RequestContext.Repair] {
        seen.withLock { seen in repairs.filter { seen.insert($0).inserted } }
    }
}
