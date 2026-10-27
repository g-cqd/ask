extension Transcript {
    /// Cancellation can end a run without delivering a result for its last tool.
    mutating func finishRunProgress() {
        finishThinking()
        while items.indices.contains(where: {
            guard !jobBlocks.values.contains($0) else { return false }
            if case .tool(_, _, .running, _) = items[$0] { return true }
            return false
        }) {
            finishTool(.failed("run ended without a tool result"))
        }
    }

    var hasLiveProgress: Bool { progress.values.contains { $0.ended == nil } }

    /// Only live blocks change revision; completed blocks remain cached across animation ticks.
    mutating func advanceProgress(at instant: ContinuousClock.Instant = .now) {
        for index in progress.keys where progress[index]?.ended == nil {
            progress[index]?.sampled = instant
            progress[index]?.frame += 1
            revisions[index] = bump()
        }
    }

    mutating func finishProgress(at index: Int, now: ContinuousClock.Instant = .now) {
        guard progress[index]?.ended == nil else { return }
        progress[index]?.ended = now
        revisions[index] = bump()
    }

    mutating func finishThinking(now: ContinuousClock.Instant = .now) {
        guard let index = items.indices.last, case .thinking = items[index] else { return }
        finishProgress(at: index, now: now)
    }
}
