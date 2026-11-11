internal import TerminalKitText

extension Transcript {
    /// Removes the conversation, keeping revisions monotonic: a renderer that skipped the empty frame must not take the next item's
    /// revision for the old item's.
    public mutating func removeAll() {
        items.removeAll(keepingCapacity: true)
        revisions.removeAll(keepingCapacity: true)
        progress.removeAll(keepingCapacity: true)
        toolBlocks.removeAll(keepingCapacity: true)
        commandBlocks.removeAll(keepingCapacity: true)
        summaryBlocks.removeAll(keepingCapacity: true)
        asideBlocks.removeAll(keepingCapacity: true)
        personCommandBlocks.removeAll(keepingCapacity: true)
        forkBlocks.removeAll(keepingCapacity: true)
        interrupted.removeAll(keepingCapacity: true)
        jobBlocks.removeAll(keepingCapacity: true)
        replacements.removeAll(keepingCapacity: true)
        // Kept by block, like the rest: the next block at a place must not inherit a picture or a summary (roadmap 0208, note n28).
        toolImages.removeAll()
        imagePlacements.removeAll()
        choiceSummaryAt = nil
        toolPaths.removeAll(keepingCapacity: true)
        outputSpans.removeAll()
        completedJobs.removeAll(keepingCapacity: true)
        folds.clearChoices()
        codeFolds.clearChoices()
    }
}
