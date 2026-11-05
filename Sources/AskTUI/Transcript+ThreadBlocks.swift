/// The blocks a thread leaves in the conversation it was forked from (roadmap 0195): where it started, prominent and open in the
/// aside's colour; and where it merged, folded like a compaction's summary, opening onto what it reported.
extension Transcript {
    /// Adds the block `update` describes; any other update adds nothing.
    mutating func addThreadBlock(_ update: ConversationUpdate) {
        switch update {
            case .threadStarted(let id, let name, let prompt, let subagent):
                startTool(name: name, summary: "started here · " + prompt, id: id)
                // A subagent sees only what the model gave it (roadmap 0063); a thread, everything up to here.
                let given =
                    subagent
                    ? "\(name) is a subagent the model started here, with only its task, and works on it beside this conversation."
                    : "\(name) was forked from this point, with the conversation up to here, and works on this beside it."
                finishTool(
                    .succeeded,
                    output: given
                        + " Open it from the sidebar or the job list (/jobs) to follow it and talk to it; when it ends, "
                        + (subagent ? "its report is the model's answer here." : "its summary merges back here."),
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
