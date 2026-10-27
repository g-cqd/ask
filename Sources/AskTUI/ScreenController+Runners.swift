/// What is running beside the conversation: the status line counts it, and a click on the count or `/tasks` opens the list.
extension ScreenController {
    mutating func setRunners(_ list: [RunnerInfo], at instant: ContinuousClock.Instant = .now) {
        var progress: [String: BlockProgress] = [:]
        for runner in list where runner.kind == .job && runner.state.isActive {
            var clock =
                state.runnerProgress[runner.id]
                ?? BlockProgress(at: runner.startedAt ?? instant, spinner: options.spinner)
            clock.sampled = instant
            progress[runner.id] = clock
        }
        state.runnerProgress = progress
        state.runners = list
        if list.isEmpty { state.runnersOpen = false }
        if let id = state.stripSelection, !list.contains(where: { $0.id == id }) { state.stripSelection = nil }
    }

    /// Opens or closes the list. With `announcing`, a command that finds nothing running says so instead of opening nothing.
    mutating func toggleRunners(announcing: Bool = false) -> [Effect] {
        guard !state.runners.isEmpty else {
            if announcing { state.transcript.addNotice("No background jobs are running.", isError: false) }
            return []
        }
        state.runnersOpen.toggle()
        return []
    }
}
