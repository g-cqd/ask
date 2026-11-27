/// A job whose end the model is to be told of (owner, 2026-11-27): it left it running, and has not seen it end.
public struct JobEnding: Sendable, Equatable {
    /// The job's name, such as `job-3`, and the thread it was started for (nil for main's).
    public let job: (id: String, owner: String?)
    /// What the model reads: how it ended, what it printed since last seen, and where its whole output is.
    public let report: String

    public init(job id: String, owner: String?, report: String) {
        job = (id, owner)
        self.report = report
    }

    public var id: String { job.id }
    public var owner: String? { job.owner }

    public static func == (left: Self, right: Self) -> Bool { left.job == right.job && left.report == right.report }
}
