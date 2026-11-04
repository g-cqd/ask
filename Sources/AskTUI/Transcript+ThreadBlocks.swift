/// The blocks a thread leaves in the conversation it was forked from (roadmap 0195): where it started, prominent and open in the
/// aside's colour; and where it merged, folded like a compaction's summary, opening onto what it reported.
extension Transcript {
    /// Adds the block `update` describes; any other update adds nothing.
    mutating func addThreadBlock(_ update: ConversationUpdate) {
        switch update {
            case .threadStarted(let id, let name, let prompt):
                startTool(name: name, summary: "started here · " + prompt, id: id)
                finishTool(
                    .succeeded,
                    output:
                        "\(name) was forked from this point, with the conversation up to here, and works on this beside it. Open it "
                        + "from the sidebar or the job list (/jobs) to follow it and talk to it; when it ends, its summary merges back here.",
                    id: id
                )
                markAside(id: id)
                if let index = toolBlocks[id] { forkBlocks[index] = name }
            case .threadMerged(let id, let name, let prompt, let summary):
                startTool(name: name, summary: "merged · " + prompt, id: id)
                finishTool(.succeeded, output: summary, id: id)
                markSummary(id: id)
            default: break
        }
    }
}
