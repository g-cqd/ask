internal import AskAgentCore
internal import Synchronization

extension JobTable {
    /// The ends the model is to be told of, as they come. Each is sent to every listener once.
    public func endings() -> AsyncStream<JobEnding> {
        endListeners.stream()
    }

    /// `job` ended: when the model is to be told, every listener hears it.
    func announceEnd(of job: Job) {
        guard job.claimEndNotice() else { return }
        let result = JobWaiting.ended(
            job,
            headline: "[\(job.id) (display [#\(job.displayID)]), which you left running, \(Self.ending(job.status))]"
        )
        let ending = JobEnding(job: job.id, owner: owner(of: job.id), report: result.content)
        endListeners.send(ending)
    }

    private static func ending(_ status: JobStatus) -> String {
        switch status {
            case .exited(0): "ended"
            case .exited(let code): "ended with exit status \(code)"
            case .stopped: "was stopped"
            case .signalled(let signal): "ended on signal \(signal)"
            case .failedToStart: "could not start"
            case .running: "is running"
        }
    }
}
