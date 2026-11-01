/// A session loaded from a possibly damaged log, with every repair that was needed.
public struct RecoveredSession: Sendable, Equatable {
    /// A valid tree: re-saving it produces a log that decodes strictly with no issues.
    public let tree: SessionTree
    /// The repairs, in line order. Empty for an undamaged log.
    public let issues: [SessionLogIssue]
    /// The header version read; missing-header recovery uses this build's writer version.
    public let formatVersion: Int
    /// For a framed file: its header, the frames read cleanly, and its data key; nil for JSONL.
    let framing: FramedOpening?

    init(
        tree: SessionTree,
        issues: [SessionLogIssue],
        formatVersion: Int = SessionLog.formatVersion,
        framing: FramedOpening? = nil
    ) {
        self.tree = tree
        self.issues = issues
        self.formatVersion = formatVersion
        self.framing = framing
    }
}
