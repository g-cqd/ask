/// Waiting on a job with a time limit, shared by the job tools.
enum JobWaiting {
    enum Outcome: Sendable, Equatable {
        case found
        case ended
        case timedOut
        case cancelled
    }

    /// Waits up to `seconds` for `job` to print `needle`, or with no needle to end.
    /// - Parameters:
    ///   - job: the job.
    ///   - needle: the bytes to wait for, or nil to wait for the end.
    ///   - seconds: the limit.
    ///   - clock: what the limit is measured on.
    /// - Returns: what came first.
    static func wait(for job: Job, needle: [UInt8]?, seconds: Int, clock: any Clock<Duration>) async -> Outcome {
        await withTaskGroup(of: Outcome?.self) { group in
            group.addTask { await watch(job, for: needle) }
            group.addTask { await expiry(after: seconds, on: clock) }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .cancelled
        }
    }

    /// `.found` or `.ended` for a job, as ``Job/wait(for:)`` reports it; nil when cancelled.
    static func watch(_ job: Job, for needle: [UInt8]?) async -> Outcome? {
        switch await job.wait(for: needle) {
            case .found: .found
            case .ended: .ended
            case .cancelled: nil
        }
    }

    /// `.timedOut` after `seconds` on `clock`; nil when cancelled first, by whatever finished before it.
    static func expiry(after seconds: Int, on clock: any Clock<Duration>) async -> Outcome? {
        (try? await clock.sleep(for: .seconds(seconds))) != nil ? .timedOut : nil
    }

    /// `, whole output in <path>` when the job has a file.
    static func fileNote(_ job: Job) -> String { job.outputPath.map { "; whole output in \($0)" } ?? "" }

    /// A line naming the job's file, when it has one.
    static func fileLine(_ job: Job) -> String { job.outputPath.map { "[whole output in \($0)]\n" } ?? "" }
}
