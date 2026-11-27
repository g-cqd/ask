internal import AskAgentCore

extension BashTool {
    /// What the call returns once its wait is over: the output of a command that ended, a job still running in the background,
    /// or an error for one that was stopped.
    static func output(
        of outcome: JobWaiting.Outcome,
        job: Job,
        readiness: ShellReadiness?,
        yield: Int?,
        limit: Int,
        notifies: Bool
    ) async -> ToolOutput {
        switch outcome {
            case .found where job.status != .running: return Self.finished(job)
            case .found:
                return Self.running(
                    job,
                    "[\(job.id) \(readiness?.headline ?? "ready"); still running]",
                    notifies: notifies
                )
            case .ended: return Self.finished(job)
            case .backgrounded where job.status != .running: return Self.finished(job)
            case .backgrounded:
                return Self.running(
                    job,
                    "[sent to the background by the person as \(job.id)\(JobWaiting.fileNote(job)); display [#\(job.displayID)]; "
                        + "it goes on; use job to inspect, send input, or stop]",
                    notifies: notifies
                )
            case .timedOut where readiness == nil && yield != nil:
                return Self.running(
                    job,
                    "[still running as \(job.id) after \(limit) s\(JobWaiting.fileNote(job)); "
                        + "display [#\(job.displayID)]; use job to inspect, send input, or stop]",
                    notifies: notifies
                )
            case .timedOut, .cancelled:
                job.stop()
                await job.ended()
                return .error(
                    Self.body(job.takeOutput())
                        + (outcome == .cancelled
                            ? Self.abortedMark
                            : "\(Self.timedOutMark) \(limit) s; the command and its children were stopped]")
                )
        }
    }

    /// A command left running as a job: its output so far, then `note`.
    static func running(_ job: Job, _ note: String, notifies: Bool) -> ToolOutput {
        job.markBackgrounded()
        // The model is told when it ends, so it may do something else meanwhile (owner, 2026-11-27); the person's own are theirs.
        job.notifyOnEnd(notifies)
        return ToolOutput(body(job.takeOutput()) + note + (notifies ? Self.endNoticeLine : ""), backgroundJob: job.id)
    }

    /// What a job left running tells the model about its end.
    static let endNoticeLine = "\n[you will be told when it ends, so you need not wait; job action quiet not to be]"
}
