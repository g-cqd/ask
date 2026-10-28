extension ScreenController {
    var hasLiveProgress: Bool {
        state.running || state.compacting || !state.runnerProgress.isEmpty
            || (state.lane?.stashed ?? state.transcript).hasLiveProgress
    }

    mutating func advanceProgress(at instant: ContinuousClock.Instant = .now) {
        for id in state.runnerProgress.keys {
            state.runnerProgress[id]?.sampled = instant
            state.runnerProgress[id]?.frame += 1
        }
        _ = onMain { controller in
            controller.holdingView { controller in
                controller.state.statusFrame += 1
                controller.state.transcript.advanceProgress(at: instant)
                return []
            }
        }
    }
}
