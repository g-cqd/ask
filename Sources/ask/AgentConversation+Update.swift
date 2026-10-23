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
            case .toolStarted(_, let name, let input):
                return .toolStarted(name: name, summary: toolSummary(name: name, input: input))
            case .toolFinished(_, _, let output):
                let last = output.content.split(separator: "\n").last.map(String.init) ?? ""
                return .toolFinished(output.isError ? .failed(last) : .succeeded, output: output.content)
            case .repaired(let repairs):
                return .notice("Repaired the context before this turn: \(repairs)", isError: false)
            case .compacted, .compactionFailed:
                return compactionNotice(event).map { .notice($0, isError: false) }
            case .continuedAtOutputLimit:
                return .notice("The response hit the output limit; asking the model to continue.", isError: false)
            case .retrying(let attempt, let total, let delay, let reason):
                return .notice(retryNotice(attempt: attempt, of: total, delay: delay, reason: reason), isError: false)
            default: return nil
        }
    }
}
