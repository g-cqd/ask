internal import AskTools

/// When each job last wrote, so the list spins for one that writes and marks a quiet one $ (note n15).
enum JobActivity {
    /// Tells `changed` what changed of `jobs`' activity, sampled every `interval` while a job runs and sent only when it changed.
    /// With no job running it waits for one to start (energy audit 2026-11-22, ENG-05): sampling every second regardless woke an
    /// idle ask 3,600 times an hour.
    static func follow(
        _ jobs: JobTable,
        every interval: Duration = .seconds(1),
        changed: @Sendable ([String: ContinuousClock.Instant]) -> Void
    ) async {
        var told: [String: ContinuousClock.Instant] = [:]
        for await list in jobs.changes() where !list.isEmpty {
            while !Task.isCancelled, !jobs.running.isEmpty {
                let seen = jobs.activity
                let fresh = seen.filter { told[$0.key] != $0.value }
                if !fresh.isEmpty { changed(fresh) }
                told = seen
                try? await Task.sleep(for: interval)
            }
        }
    }
}
