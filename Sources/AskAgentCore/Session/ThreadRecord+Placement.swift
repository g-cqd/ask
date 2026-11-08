extension ThreadRecord {
    /// The entry of `branch` this record's block is shown after when a session is replayed (roadmap 0195).
    ///
    /// A start is shown where it forked: the thread saw that much of the conversation. A merge is recorded at the parent's leaf at the
    /// time, but its summary goes with what the parent is sent next, so it is shown at the end of the turn it came in: the last entry
    /// before the next prompt, or the branch's last. Merged while the parent worked, it would otherwise come before that turn's later
    /// replies (the audit of 2026-11-06). An entry not on the branch, or none, is returned as it is.
    public func shown(in branch: [SessionEntry]) -> EntryID? {
        guard event == .merged, let at, let start = branch.firstIndex(where: { $0.id == at }) else { return at }
        var end = start
        for index in branch.indices.dropFirst(start + 1) {
            if case .user = branch[index].payload { break }
            end = index
        }
        return branch[end].id
    }
}
