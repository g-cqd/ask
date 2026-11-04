/// A thread's conversation (roadmap 0194), which looks like the one it was forked from.
extension Transcript {
    /// An empty transcript drawn as this one is (its folds' defaults, Markdown, colours, durations, home), with revisions and a row
    /// cache of its own.
    func emptyLike(revisionBase: Int) -> Transcript {
        var copy = Transcript(revisionBase: revisionBase)
        copy.shimmer = shimmer
        copy.toolsFoldedByDefault = toolsFoldedByDefault
        copy.thinkingFoldedByDefault = thinkingFoldedByDefault
        copy.codeFoldedByDefault = codeFoldedByDefault
        copy.codeFoldLines = codeFoldLines
        copy.outputFoldLines = outputFoldLines
        copy.outputFoldBytes = outputFoldBytes
        copy.markdown = markdown
        copy.tokenNames = tokenNames
        copy.highlight = highlight
        copy.spinnerStyle = spinnerStyle
        copy.localizedDurations = localizedDurations
        copy.timeoutDisplay = timeoutDisplay
        copy.timeoutLabel = timeoutLabel
        copy.home = home
        return copy
    }
}
