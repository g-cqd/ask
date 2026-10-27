internal import AskAI
internal import AskAgentCore
internal import AskTUI

extension AgentConversation {
    /// What the screen shows for one loop event, or nil when it shows nothing.
    static func update(for event: AgentEvent) -> ConversationUpdate? {
        switch event {
            case .model(.textDelta(_, let text)): return .assistantText(text)
            case .model(.thinkingDelta(_, let text)): return .thinkingText(text)
            case .model(.notice(let text)): return .notice(text, isError: false)
            case .promptAccepted(let prompt): return .promptAccepted(id: prompt.id, text: prompt.text)
            case .toolStarted(let id, let name, let input):
                return .toolStarted(
                    name: name == "bash" ? "shell" : name, summary: ToolSummary.header(for: input), id: id,
                    fullInput: ToolSummary.fullInput(for: input))
            case .toolFinished(let id, _, let output):
                let last = output.content.split(separator: "\n").last.map(String.init) ?? ""
                return .toolFinished(
                    output.isError ? .failed(last) : .succeeded, output: output.content,
                    id: id, backgroundJob: output.backgroundJob)
            case .repaired(let repairs):
                return .notice("Repaired the context before this turn: \(repairs)", isError: false)
            case .compacted, .compactionFailed:
                return RunNotices.compaction(for: event).map { .notice($0, isError: false) }
            case .continuedAtOutputLimit:
                return .detail("The response hit the output limit; asking the model to continue.")
            case .retrying(let attempt, let total, let delay, let reason):
                return .notice(
                    RunNotices.retry(attempt: attempt, of: total, delay: delay, reason: reason), isError: false)
            default: return nil
        }
    }
}
