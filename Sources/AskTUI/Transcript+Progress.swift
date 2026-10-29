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

    /// The person stopped the turn (roadmap 0142): every block still going, reasoning and foreground tools, ends now and turns orange.
    /// Background jobs go on. A tool's result arriving later is still kept.
    mutating func interruptRunning(at now: ContinuousClock.Instant = .now) {
        if let index = items.indices.last, case .thinking(let text) = items[index], Self.saysSomething(text),
            progress[index]?.ended == nil
        {
            interrupted.insert(index)
            revisions[index] = bump()
        }
        finishThinking(now: now)
        while let index = latestForegroundTool,
            case .tool(let name, let summary, _, let output, let input) = items[index]
        {
            finishProgress(at: index, now: now)
            interrupted.insert(index)
            items[index] = .tool(name: name, summary: summary, status: .interrupted, output: output, fullInput: input)
            revisions[index] = bump()
        }
    }

    /// Adds a queued message with a spinner of its own.
    mutating func addQueued(_ text: String, now: ContinuousClock.Instant = .now) {
        append(.queued(text))
        progress[items.count - 1] = BlockProgress(at: now, spinner: spinnerStyle)
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
