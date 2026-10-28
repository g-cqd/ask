internal import TerminalKitText

extension Transcript {
    /// Yielded jobs outlive the turn, so they are not candidates for its implicit tool completion.
    var latestForegroundTool: Int? {
        items.indices.last {
            guard !jobBlocks.values.contains($0) else { return false }
            if case .tool(_, _, .running, _, _) = items[$0] { return true }
            return false
        }
    }

    /// Cancellation can end a run without delivering a result for its last tool.
    mutating func finishRunProgress() {
        finishThinking()
        while latestForegroundTool != nil {
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

    /// Ends the thinking block that is last, if one is. One that said nothing (roadmap 0081: empty, only white space, as a provider that
    /// hides its reasoning streams it) is dropped instead: live, its spinner said the model was thinking; ended, it would be a header that
    /// opens on nothing. Only the screen loses it: the session file and what is sent back to the provider keep the block.
    mutating func finishThinking(now: ContinuousClock.Instant = .now) {
        guard let index = items.indices.last, case .thinking(let text) = items[index] else { return }
        guard Self.saysSomething(text) else {
            items.removeLast()
            revisions.removeLast()
            progress[index] = nil
            folds.clearChoice(for: index)
            return
        }
        finishProgress(at: index, now: now)
    }
}
