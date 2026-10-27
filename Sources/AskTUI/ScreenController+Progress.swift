extension ScreenController {
    var hasLiveProgress: Bool { (state.lane?.stashed ?? state.transcript).hasLiveProgress }

    mutating func advanceProgress(at instant: ContinuousClock.Instant = .now) {
        _ = onMain { controller in
            controller.holdingView { controller in
                controller.state.transcript.advanceProgress(at: instant)
                return []
            }
        }
    }
}
