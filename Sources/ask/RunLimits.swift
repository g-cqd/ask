/// The command line's limits on one run, as the loop's settings take them.
struct RunLimits {
    /// The most model requests one prompt may make.
    var maximumTurns: Int
    /// The context size that triggers compaction, or nil for only when the window is full.
    var compactAtTokens: Int?
}
