internal import Synchronization

extension Job {
    /// Keep the background job's file available after wait/job_stop consumes its model-facing result.
    func markBackgrounded() { state.withLock { $0.backgrounded = true } }

    func snapshot(output: String?) -> JobSnapshot {
        state.withLock { state in
            let tail = String(decoding: state.recent, as: UTF8.self)
            let note = state.totalBytes > state.recent.count ? "… earlier output not shown\n" : ""
            let lines = state.totalLines + (state.recent.last.map { $0 == 0x0A ? 0 : 1 } ?? 0)
            return JobSnapshot(
                id: id, output: output ?? note + tail, status: state.status, startedAt: startedAt,
                endedAt: state.endedAt, lines: lines)
        }
    }
}
