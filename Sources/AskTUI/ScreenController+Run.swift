/// Starting, refusing and stopping a run.
extension ScreenController {
    /// Says so, and returns true, when a turn is still running.
    mutating func busy() -> Bool {
        guard state.running else { return false }
        state.transcript.addNotice("A turn is still running; press Ctrl+C to stop it first.", isError: false)
        return true
    }

    mutating func begin(_ effect: Effect) -> [Effect] {
        if case .startRun = effect { acceptsInput = true } else { acceptsInput = false }
        returningInput = false
        interruptedByPerson = false
        state.abortArmedAt = nil
        state.abortArmedAction = nil
        state.running = true
        state.statusSpinner = options.spinner.resolved()
        state.statusFrame = 0
        state.scrollback = 0
        return [effect]
    }

    mutating func abort() -> [Effect] {
        returningInput = true
        interruptedByPerson = true
        // No block says so: what was still going turns orange (roadmap 0142).
        state.transcript.interruptRunning()
        return [.cancelRun]
    }
}
