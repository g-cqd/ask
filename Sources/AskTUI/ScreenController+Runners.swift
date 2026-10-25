/// What is running beside the conversation: the status line counts it, and a click on the count or `/tasks` opens the list.
extension ScreenController {
    mutating func setRunners(_ list: [RunnerInfo]) {
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
