/// Blocks whose output is a summary ask wrote (roadmap 0176): a compaction's, drawn as Markdown when open and headed by what it did.
extension Transcript {
    /// Marks the tool block started as `id` as a summary block.
    mutating func markSummary(id: String) {
        guard let index = toolBlocks[id] else { return }
        summaryBlocks.insert(index)
    }

    /// Gives the tool block started as `id` a new header text, the part after its name.
    mutating func renameTool(summary: String, id: String) {
        guard let index = toolBlocks[id], case .tool(let name, _, let status, let output, let input) = items[index]
        else { return }
        items[index] = .tool(name: name, summary: summary, status: status, output: output, fullInput: input)
        revisions[index] = bump()
    }
}
