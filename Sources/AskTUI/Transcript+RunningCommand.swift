extension Transcript {
    /// Whether a command's block is running (roadmap 0173).
    var hasRunningCommand: Bool {
        commandBlocks.contains { index in
            guard items.indices.contains(index), case .tool(_, _, .running, _, _) = items[index] else { return false }
            return true
        }
    }
}
