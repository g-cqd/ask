extension BashTool {
    /// A readiness wait must also finish when the process exits, and cancel its other observers.
    static func waitForPort(_ port: Int, job: Job, seconds: Int, clock: any Clock<Duration>) async -> JobWaiting.Outcome
    {
        await withTaskGroup(of: JobWaiting.Outcome?.self) { group in
            group.addTask { await PortWait.until(open: port, clock: clock) ? .found : nil }
            group.addTask { await JobWaiting.watch(job, for: nil) }
            group.addTask { await JobWaiting.expiry(after: seconds, on: clock) }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result ?? .cancelled
        }
    }
}
