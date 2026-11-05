/// What is running beside the conversation: the status line counts it, and a click on the count or `/jobs` opens the list.
extension ScreenController {
    mutating func setRunners(_ list: [RunnerInfo], at instant: ContinuousClock.Instant = .now) {
        var progress: [String: BlockProgress] = [:]
        for runner in list where runner.state.isActive {
            var clock =
                state.runnerProgress[runner.id]
                ?? BlockProgress(at: runner.startedAt ?? instant, spinner: options.spinner)
            clock.sampled = instant
            progress[runner.id] = clock
        }
        state.runnerProgress = progress
        state.runnerActivity = state.runnerActivity.filter { progress[$0.key] != nil }
        state.runners = list
        for runner in list where runner.kind == .agent && runner.state == .merged && state.mergedAt[runner.id] == nil {
            state.mergedAt[runner.id] = instant
        }
        expireMerged(at: instant)
        // Another session's threads (roadmap 0195): their conversations go with them.
        let listed = Set(list.lazy.filter { $0.kind == .agent }.map(\.id))
        state.threads = state.threads.filter { listed.contains($0.key) }
        // `/threads` lists them by name and state, which this list just changed (roadmap 0195).
        state.choices["threads"]?.stale = true
        asking.remove("threads")
        if list.isEmpty { state.runnersOpen = false }
        if let id = state.stripSelection, !list.contains(where: { $0.id == id }) { state.stripSelection = nil }
    }

    /// Opens or closes the list. With `announcing`, a command that finds nothing running says so instead of opening nothing.
    /// Leaves out of the sidebar the threads merged longer than `threads.mergedShownFor` (note n22); `/threads` still lists them.
    mutating func expireMerged(at instant: ContinuousClock.Instant) {
        guard let shownFor = options.mergedShownFor else { return }
        let expired = Set(state.mergedAt.filter { instant - $0.value >= shownFor }.keys)
        if expired != state.expiredMerged { state.expiredMerged = expired }
    }

    mutating func toggleRunners(announcing: Bool = false) -> [Effect] {
        guard !state.runners.isEmpty else {
            if announcing { state.transcript.addNotice("No background jobs are running.", isError: false) }
            return []
        }
        // One list at a time: the sidebar already lists them.
        if Sidebar.isShown(state, columns: frame.columns), !state.runnersOpen {
            if announcing {
                state.transcript.addNotice(
                    "The sidebar lists them. Close it (Ctrl+\\ or /sidebar) to have the list below the input instead.",
                    isError: false
                )
            }
            return []
        }
        state.runnersOpen.toggle()
        return []
    }
}
