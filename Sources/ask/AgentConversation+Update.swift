internal import AskAI
internal import AskAgentCore
internal import AskTUI
internal import AskTools

extension AgentConversation {
    /// What the screen shows for one loop event: nothing, or one update, or two when a connection drops.
    static func updates(for event: AgentEvent) -> [ConversationUpdate] {
        switch event {
            case .compacting: return [.compacting(true)]
            // A dropped connection is said by the status bar while ask waits to try again, not by a block; the reason is a detail, shown
            // with --verbose.
            case .retrying(let attempt, let total, let delay, let reason):
                return [
                    .reconnecting(true),
                    .detail(RunNotices.retry(attempt: attempt, of: total, delay: delay, reason: reason))
                ]
            case .waitingForNetwork: return [.waitingForNetwork]
            case .compacted(let summary, _): return [.compactionFinished(.succeeded, text: summary)]
            case .compactionFailed(let reason): return [.compactionFinished(.failed("failed"), text: reason)]
            default: return update(for: event).map { [$0] } ?? []
        }
    }

    /// What the screen shows for one loop event other than a compaction's, or nil when it shows nothing.
    private static func update(for event: AgentEvent) -> ConversationUpdate? {
        switch event {
            case .model(.textDelta(_, let text)): return .assistantText(text)
            case .model(.thinkingDelta(_, let text)): return .thinkingText(text)
            case .model(.notice(let text)): return .notice(text, isError: false)
            case .promptAccepted(let prompt): return .promptAccepted(id: prompt.id, text: prompt.text)
            case .toolStarted(let id, let name, let input):
                return .toolStarted(
                    name: name == "bash" ? "shell" : name, summary: ToolSummary.header(for: input), id: id,
                    fullInput: ToolSummary.fullInput(for: input),
                    command: ToolSummary.commandLimits(for: input)
                        .map {
                            ToolCommand(
                                timeout: $0.timeout.map(Duration.seconds), yield: $0.yield.map(Duration.seconds),
                                defaultTimeout: .seconds(BashTool.defaultTimeout))
                        })
            case .toolFinished(let id, _, let output):
                let last = output.content.split(separator: "\n").last.map(String.init) ?? ""
                return .toolFinished(
                    output.isError ? .failed(last) : .succeeded, output: output.content,
                    id: id, backgroundJob: output.backgroundJob)
            case .repaired(let repairs):
                return .notice("Repaired the context: \(RequestContext.describe(repairs)).", isError: false)
            case .continuedAtOutputLimit:
                return .detail("The response hit the output limit; asking the model to continue.")
            default: return nil
        }
    }
}
