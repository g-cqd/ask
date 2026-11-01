extension ScreenController {
    var hasLiveProgress: Bool {
        state.running || state.compacting || state.reconnecting || !state.runnerProgress.isEmpty
            || (state.lane?.stashed ?? state.transcript).hasLiveProgress
    }

    /// Whether a running header shimmers (roadmap 0187), which wants the progress timer's faster tick.
    var isShimmering: Bool {
        let transcript = state.lane?.stashed ?? state.transcript
        return transcript.shimmer && transcript.hasLiveProgress
    }

    /// A tick: the spinners step when `advancingFrames`; live blocks are redrawn either way, for the shimmer.
    mutating func advanceProgress(at instant: ContinuousClock.Instant = .now, advancingFrames: Bool = true) {
        for id in state.runnerProgress.keys {
            state.runnerProgress[id]?.sampled = instant
            if advancingFrames { state.runnerProgress[id]?.frame += 1 }
        }
        _ = onMain { controller in
            controller.holdingView { controller in
                if advancingFrames { controller.state.statusFrame += 1 }
                controller.state.transcript.advanceProgress(at: instant, advancingFrames: advancingFrames)
                return []
            }
        }
    }
}
