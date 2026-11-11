extension ScreenController {
    /// Whether the screen is at work for the tab's progress (note n59): a turn, a compaction, or a command in the foreground, such
    /// as the person's `!` one outside any turn. A background job or an aside is not; nor is reconnecting, which is waiting.
    var isWorking: Bool {
        state.running || state.compacting || state.transcript.latestForegroundTool != nil
    }

    var hasLiveProgress: Bool {
        state.running || state.compacting || state.reconnecting || !state.runnerProgress.isEmpty
            || (state.lane?.stashed ?? state.transcript).hasLiveProgress
            || (state.lane?.isThread == true && state.transcript.hasLiveProgress)
    }

    /// Whether a running header shimmers (roadmap 0187), which wants the progress timer's faster tick.
    var isShimmering: Bool {
        let transcript = state.lane?.stashed ?? state.transcript
        return transcript.shimmer && transcript.hasLiveProgress
    }

    /// A tick: the spinners step when `advancingFrames`; live blocks are redrawn either way, for the shimmer.
    mutating func advanceProgress(at instant: ContinuousClock.Instant = .now, advancingFrames: Bool = true) {
        expireMerged(at: instant)
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
        // A thread's lane shows its own conversation, whose blocks run too.
        if state.lane?.isThread == true {
            state.transcript.advanceProgress(at: instant, advancingFrames: advancingFrames)
        }
    }
}
