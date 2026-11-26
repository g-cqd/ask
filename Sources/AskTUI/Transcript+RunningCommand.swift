extension Transcript {
    /// Whether a command's block is running (roadmap 0173).
    var hasRunningCommand: Bool {
        commandBlocks.contains { index in
            guard items.indices.contains(index), case .tool(_, _, .running, _, _) = items[index] else { return false }
            return true
        }
    }

    /// Whether the model waits on something the person may send to the background: a running command, or a `job` call that waits
    /// (owner, 2026-11-26). Read for Ctrl+B only, so the scan of the newest blocks is not on every key.
    var hasRunningWait: Bool {
        hasRunningCommand
            || items.reversed().prefix(64)
                .contains { item in
                    guard case .tool("job", _, .running, _, _) = item else { return false }
                    return true
                }
    }
}
