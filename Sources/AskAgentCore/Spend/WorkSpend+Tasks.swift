extension WorkSpend {
    /// What the session spent while `task` was in progress, from its last start to when it was done, on `tree`'s active branch (roadmap
    /// 0239): everything recorded meanwhile, so two tasks in progress at once each count it. Nil for a task not done, or never started.
    public static func of(_ task: SessionTask, in tree: SessionTree) -> WorkSpend? {
        guard task.state == .done, let started = task.started, let finished = task.finished, finished >= started else {
            return nil
        }
        // To the millisecond: the response that asked to start it and the result that says it is done are not its own.
        return WorkSpend(of: tree.activeBranch().filter { $0.recordedAt.map((started ... finished).contains) ?? false })
    }
}
