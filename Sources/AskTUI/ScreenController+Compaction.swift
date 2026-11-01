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
            case .compactionFinished(let status, let text, let tokens):
                finishCompactionBlock(status, text: text, tokens: tokens)
            case .reconnecting(let waiting):
                state.reconnecting = waiting
                if waiting { state.waitingForNetwork = false }
            case .waitingForNetwork: state.waitingForNetwork = true
            case .connectingMCP(let waiting): state.connectingMCP = waiting
            default: break
        }
    }

    /// The model answers again: whatever the status bar said about waiting for it is over.
    mutating func modelIsBack() {
        state.reconnecting = false
        state.waitingForNetwork = false
    }

    mutating func startCompactionBlock() {
        state.transcript.startTool(name: "compaction", summary: "earlier messages", id: Self.compactionBlock)
        state.transcript.markSummary(id: Self.compactionBlock)
    }

    /// Ends the running compaction block with `text`, the summary or the reason; when none was started, adds one that is already done.
    /// `tokens`, when given, takes the header's place: what was summarised into what (roadmap 0176).
    mutating func finishCompactionBlock(_ status: Transcript.ToolStatus, text: String, tokens: String? = nil) {
        if !state.compacting { startCompactionBlock() }
        state.compacting = false
        if let tokens { state.transcript.renameTool(summary: tokens, id: Self.compactionBlock) }
        state.transcript.finishTool(status, output: text, id: Self.compactionBlock)
    }
}
