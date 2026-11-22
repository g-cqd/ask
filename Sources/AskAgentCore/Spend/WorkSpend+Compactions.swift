extension WorkSpend {
    /// What the session spent from one compaction to the next on `tree`'s active branch, oldest first (roadmap 0239): one stretch for
    /// each compaction, ending at it; the work since the last compaction is not a stretch yet.
    public static func compactionStretches(in tree: SessionTree) -> [WorkSpend] {
        let branch = tree.activeBranch()
        var stretches: [WorkSpend] = []
        var start = branch.startIndex
        for index in branch.indices where branch[index].kind == .compaction {
            stretches.append(WorkSpend(of: branch[start ..< index]))
            start = index + 1
        }
        return stretches
    }

    /// The time spent waiting for the model and the tools, leaving out the person's own between a reply and the next prompt: a stretch
    /// between compactions can span a night. Nil when neither is known.
    public var workingMilliseconds: Int? {
        switch (modelMilliseconds, toolMilliseconds) {
            case (nil, nil): nil
            default: (modelMilliseconds ?? 0) + (toolMilliseconds ?? 0)
        }
    }
}
