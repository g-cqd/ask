internal import AskTUI
internal import AskTools

extension AgentConversation {
    func watchJob(_ id: String, update: @escaping @Sendable (JobUpdate) -> Void) -> Task<Void, Never> {
        let jobs = jobs
        return Task {
            for await _ in jobs.outputChanges(of: id) {
                guard !Task.isCancelled else { return }
                if let snapshot = jobs.snapshot(of: id) {
                    update(Self.screenJob(snapshot))
                    if snapshot.status != .running { return }
                }
                // Coalesce a noisy process's notifications before allocating another 64 KiB UI snapshot.
                try? await Task.sleep(for: .milliseconds(100))
            }
            // The closing stream carries no element: read once more for final output and exit status.
            guard !Task.isCancelled else { return }
            if let snapshot = jobs.snapshot(of: id) { update(Self.screenJob(snapshot)) }
        }
    }

    private static func screenJob(_ snapshot: JobSnapshot) -> JobUpdate {
        let status: Transcript.ToolStatus
        let ending: String
        switch snapshot.status {
            case .running:
                status = .running
                ending = "running"
            case .exited(0):
                status = .succeeded
                ending = "ended"
            case .exited(let code):
                status = .failed("[exit \(code)]")
                ending = "failed"
            case .stopped:
                status = .failed("stopped")
                ending = "stopped"
            case .signalled(let signal):
                status = .failed("signal \(signal)")
                ending = "signalled"
            case .failedToStart:
                status = .failed("could not start")
                ending = "failed"
        }
        return JobUpdate(
            id: snapshot.id, label: "#" + snapshot.displayID, output: snapshot.output, status: status,
            startedAt: snapshot.startedAt, endedAt: snapshot.endedAt, lines: snapshot.lines, ending: ending)
    }
}
