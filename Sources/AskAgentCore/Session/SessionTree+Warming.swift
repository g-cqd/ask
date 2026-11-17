extension SessionTree {
    /// What a request, the screen's replay and a rewind's menu read at any moment: the active branch from the last compaction's first
    /// kept entry on (the whole branch without one), root side first; and how many entries of the branch come before it.
    /// - Complexity: O(depth).
    public func sinceLastCompaction() -> (entries: [SessionEntry], earlier: Int) {
        let branch = activeBranch()
        guard let last = branch.lastIndex(where: { $0.kind == .compaction }),
            case .compaction(_, let kept) = branch[last].payload,
            let first = branch.firstIndex(where: { $0.id == kept })
        else { return (branch, 0) }
        return (Array(branch[first...]), first)
    }

    /// Holds the payloads of the warm entries, which opening left in the file until the active branch was known. One the file no
    /// longer has stays as it is, and reads as unreadable.
    mutating func holdWarm() {
        for entry in sinceLastCompaction().entries where entry.isInFile {
            guard let position = positions[entry.id], let held = entry.holding() else { continue }
            entries[position] = held
        }
    }

    /// Holds every payload, so that nothing reads the file again: before it is replaced.
    /// - Returns: the entries whose payload the file no longer has; none held then, if any, and the tree unchanged.
    mutating func holdAll() -> [EntryID] {
        var held: [Int: SessionEntry] = [:]
        var missing: [EntryID] = []
        for index in entries.indices where entries[index].isInFile {
            if let entry = entries[index].holding() { held[index] = entry } else { missing.append(entries[index].id) }
        }
        guard missing.isEmpty else { return missing }
        for (index, entry) in held { entries[index] = entry }
        return []
    }

    /// How many entries are left in the session file.
    public var inFileCount: Int { entries.reduce(0) { $0 + ($1.isInFile ? 1 : 0) } }
}
