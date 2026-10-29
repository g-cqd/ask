/// A compaction as a block of the conversation (roadmap 0105): a tool-style block, so it has the spinner, the time, the status, the fold and
/// the text it opens onto without a second implementation.
extension ScreenController {
    static let compactionBlock = "compaction"

    /// What the status bar and the conversation say about work that is not a turn: a compaction under way or ended, and a lost connection.
    mutating func applyBackgroundWork(_ update: ConversationUpdate) {
        switch update {
            case .compacting(let active):
                state.compacting = active
                if active { startCompactionBlock() }
            case .compactionFinished(let status, let text): finishCompactionBlock(status, text: text)
            case .reconnecting(let waiting): state.reconnecting = waiting
            case .connectingMCP(let waiting): state.connectingMCP = waiting
            default: break
        }
    }

    mutating func startCompactionBlock() {
        state.transcript.startTool(name: "compact", summary: "earlier messages", id: Self.compactionBlock)
    }

    /// Ends the running compaction block with `text`, the summary or the reason; when none was started, adds one that is already done.
    mutating func finishCompactionBlock(_ status: Transcript.ToolStatus, text: String) {
        if !state.compacting { startCompactionBlock() }
        state.compacting = false
        state.transcript.finishTool(status, output: text, id: Self.compactionBlock)
    }
}
