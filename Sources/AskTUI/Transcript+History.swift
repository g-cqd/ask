internal import TerminalKitText

/// `ui.historyLimit` (note n29): letting the oldest blocks go once the conversation holds more than the limit (``HistoryTrim``).
extension Transcript {
    /// Lets the oldest blocks go until no more than the limit are kept, or only blocks still going and the newest are left.
    mutating func trimHistory() {
        guard let limit = history.limit else { return }
        var excess = items.count - history.trimmed - limit
        var gone: [Int] = []
        var index = history.next
        // The newest block always stays: it was just added.
        while excess > 0, index < items.count - 1 {
            if !isGoing(index) {
                gone.append(index)
                excess -= 1
            }
            index += 1
        }
        guard !gone.isEmpty else { return }
        history.next = index
        forget(gone)
    }

    /// Whether the block at `index` is still going: a tool or reasoning that has not ended, a job, a message waiting to be taken.
    private func isGoing(_ index: Int) -> Bool {
        if let clock = progress[index], clock.ended == nil { return true }
        if jobBlocks.values.contains(index) { return true }
        switch items[index] {
            case .queued, .tool(_, _, .running, _, _): return true
            default: return false
        }
    }

    /// Empties the blocks at `indices` and everything kept about them.
    private mutating func forget(_ indices: [Int]) {
        let gone = Set(indices)
        for index in indices {
            items[index] = .trimmed
            revisions[index] = bump()
            progress[index] = nil
            for kind: WritableKeyPath<Self, Set<Int>> in [
                \.commandBlocks, \.summaryBlocks, \.asideBlocks, \.personCommandBlocks, \.interrupted
            ] {
                self[keyPath: kind].remove(index)
            }
            forkBlocks[index] = nil
            replacements[index] = nil
            toolImages[index] = nil
            imagePlacements[index] = nil
            toolPaths[index] = nil
            outputSpans[index] = nil
            folds.clearChoice(for: index)
            if choiceSummaryAt == index { choiceSummaryAt = nil }
        }
        toolBlocks = toolBlocks.filter { !gone.contains($0.value) }
        jobBlocks = jobBlocks.filter { !gone.contains($0.value) }
        history.trimmed += indices.count
        // Only the newest gone block says how many are gone: the one that said it before draws nothing now.
        let newest = Swift.max(history.boundary ?? 0, indices.max() ?? 0)
        if let previous = history.boundary, previous != newest { revisions[previous] = bump() }
        history.boundary = newest
        revisions[newest] = bump()
    }
}
