internal import AskAgentCore

/// The command line's limits on one run, as the loop's settings take them.
struct RunLimits {
    /// The most model requests one prompt may make.
    var maximumTurns: Int
    /// When compaction starts: a share of the window or a number of tokens (roadmap 0104).
    var compactAt: CompactionThreshold
}
